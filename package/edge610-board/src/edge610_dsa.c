// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/string.h>
#include <linux/delay.h>
#include <linux/pci.h>
#include <linux/bitops.h>
#include <linux/mdio.h>
#include <linux/phy.h>
#include <linux/netdevice.h>
#include <linux/platform_data/mv88e6xxx.h>
#include <net/net_namespace.h>

#define DRV "edge610-dsa"
#define P2SB_DEVICE_ID 0x19dd
#define NORTH_OFFSET 0x00c20000
#define NORTH_SIZE 0x10000
#define NORTH_BAR_SIZE 0x1000000
#define PIN_MDC 33
#define PIN_MDIO 34

#define PADCFG0_TXSTATE BIT(0)
#define PADCFG0_RXSTATE BIT(1)
#define PADCFG0_TXDIS BIT(8)
#define PADCFG0_RXDIS BIT(9)
#define PADCFG0_PMODE GENMASK(12, 10)

static void __iomem *north;
static void __iomem *pads;
static struct pci_dev *p2sb;
static struct mii_bus *edge_bus;
static struct mdio_device *switch_mdio;
static struct net_device *conduit;
static struct dsa_mv88e6xxx_pdata switch_pdata;
static char *conduit_name = "eno1";
static int force_cpu_phyctl = 0x203e;
static int force_cpu_ctl0 = -1;
static int force_cpu_map = -1;

module_param(conduit_name, charp, 0444);
MODULE_PARM_DESC(conduit_name, "Linux netdev name of the X553 switch CPU conduit");
module_param(force_cpu_phyctl, int, 0644);
MODULE_PARM_DESC(force_cpu_phyctl,
	"Override CPU port physical control register 0x01 after DSA setup (-1 disables)");
module_param(force_cpu_ctl0, int, 0644);
MODULE_PARM_DESC(force_cpu_ctl0,
	"Override CPU port control register 0x04 after DSA setup (-1 disables)");
module_param(force_cpu_map, int, 0644);
MODULE_PARM_DESC(force_cpu_map,
	"Override CPU port VLAN map register 0x06 after DSA setup (-1 disables)");

/* Which 88E6190 port is wired to the X553 function used as the conduit:
 * 10 = 0000:03:00.0 (eth0), 9 = 0000:03:00.1 (eth1). Validated on the
 * Edge 610: port 9 carries the working 1G SGMII link.
 */
static ushort cpu_port = 10;
module_param(cpu_port, ushort, 0444);
MODULE_PARM_DESC(cpu_port, "88E6190 CPU port wired to the conduit (9 or 10)");

static unsigned long p2sb_bar_addr;
module_param(p2sb_bar_addr, ulong, 0444);
MODULE_PARM_DESC(p2sb_bar_addr,
		 "P2SB MMIO BAR to use when the PCI function is hidden by BIOS (0 = autodetect)");

/* Some BIOSes hide the P2SB PCI function (00:1f.1, 8086:19dd) from the bus
 * scan while still reserving its MMIO window. There the ACPI resource
 * "INTC3000:00" covers exactly P2SB_BAR + NORTH_OFFSET, so the BAR can be
 * derived from the iomem resource tree instead of PCI enumeration.
 */
static resource_size_t p2sb_bar_from_iomem(void)
{
	struct resource *r;

	for (r = iomem_resource.child; r; r = r->sibling) {
		if (!r->name || !strstr(r->name, "INTC3000"))
			continue;
		if (resource_size(r) != NORTH_SIZE)
			continue;
		if ((r->start & (NORTH_SIZE - 1)) !=
		    (NORTH_OFFSET & (NORTH_SIZE - 1)))
			continue;
		/* The P2SB MMIO BAR is 16MB aligned; anything else is a
		 * different P2SB port window, not the BAR base.
		 */
		if ((r->start - NORTH_OFFSET) & (NORTH_BAR_SIZE - 1))
			continue;
		return r->start - NORTH_OFFSET;
	}
	return 0;
}

static void __iomem *padcfg(unsigned int pin)
{
	return pads + pin * 8;
}

static void pad_input(unsigned int pin)
{
	void __iomem *cfg = padcfg(pin);
	u32 value = readl(cfg);

	value &= ~PADCFG0_PMODE;
	value &= ~PADCFG0_RXDIS;
	value |= PADCFG0_TXDIS;
	writel(value, cfg);
	readl(cfg);
}

static void pad_output(unsigned int pin, int high)
{
	void __iomem *cfg = padcfg(pin);
	u32 value = readl(cfg);

	value &= ~PADCFG0_PMODE;
	value &= ~(PADCFG0_TXDIS | PADCFG0_RXDIS | PADCFG0_TXSTATE);
	if (high)
		value |= PADCFG0_TXSTATE;
	writel(value, cfg);
	readl(cfg);
}

static int pad_value(unsigned int pin)
{
	return !!(readl(padcfg(pin)) & PADCFG0_RXSTATE);
}

static void mdio_delay(void)
{
	udelay(3);
}

static void mdc(int high)
{
	pad_output(PIN_MDC, high);
	mdio_delay();
}

static void mdio_drive(int high)
{
	if (high)
		pad_input(PIN_MDIO);
	else
		pad_output(PIN_MDIO, 0);
	mdio_delay();
}

static void mdio_bit(int bit)
{
	mdc(0);
	mdio_drive(bit);
	mdc(1);
}

static int mdio_sample(void)
{
	int bit;

	mdc(0);
	mdio_drive(1);
	mdc(1);
	bit = pad_value(PIN_MDIO);
	return bit;
}

static void mdio_header(unsigned int phy, unsigned int reg, bool write)
{
	int i;

	for (i = 0; i < 32; i++)
		mdio_bit(1);
	mdio_bit(0);
	mdio_bit(1);
	mdio_bit(write ? 0 : 1);
	mdio_bit(write ? 1 : 0);
	for (i = 4; i >= 0; i--)
		mdio_bit((phy >> i) & 1);
	for (i = 4; i >= 0; i--)
		mdio_bit((reg >> i) & 1);
}

static int edge610_mdio_read(struct mii_bus *bus, int phy, int reg)
{
	u16 raw = 0;
	int i;

	mdio_header(phy, reg, false);
	/* The relocated PADCFG path returns the released turnaround level, but
	 * not the short low ACK pulse. The bus is dedicated and PHY scanning is
	 * disabled, so consume turnaround and use the following 16 data bits.
	 */
	(void)mdio_sample();
	for (i = 15; i >= 0; i--)
		raw |= mdio_sample() << i;
	mdc(0);
	mdio_drive(1);
	return raw;
}

static int edge610_mdio_write(struct mii_bus *bus, int phy, int reg, u16 value)
{
	int i;

	mdio_header(phy, reg, true);
	mdio_bit(1);
	mdio_bit(0);
	for (i = 15; i >= 0; i--)
		mdio_bit((value >> i) & 1);
	mdc(0);
	mdio_drive(1);
	return 0;
}

static int edge610_mdio_bus_match(struct device *dev,
				  const struct device_driver *driver)
{
	return !strcmp(to_mdio_device(dev)->modalias, driver->name);
}

static int __init edge610_dsa_init(void)
{
	resource_size_t p2sb_bar;
	struct device *host;
	u32 padbar, reg0;
	int err, port;
	u16 value;

	conduit = dev_get_by_name(&init_net, conduit_name);
	if (!conduit) {
		pr_err(DRV ": conduit %s is not available; load this module after ixgbe\n",
		       conduit_name);
		return -EPROBE_DEFER;
	}

	p2sb = pci_get_device(PCI_VENDOR_ID_INTEL, P2SB_DEVICE_ID, NULL);
	if (p2sb) {
		p2sb_bar = pci_resource_start(p2sb, 0);
	} else {
		p2sb_bar = p2sb_bar_addr ? p2sb_bar_addr : p2sb_bar_from_iomem();
		if (p2sb_bar)
			pr_info(DRV ": P2SB hidden by BIOS, BAR %pa\n",
				&p2sb_bar);
	}
	if (!p2sb_bar) {
		pr_err(DRV ": P2SB BAR unavailable (device hidden, no iomem hint); pass p2sb_bar_addr=\n");
		err = -ENODEV;
		goto fail_netdev;
	}
	/* host_dev/parent only need a valid struct device; the kernel does not
	 * dereference dsa_chip_data.host_dev for this driver. */
	host = p2sb ? &p2sb->dev : &conduit->dev;

	north = ioremap(p2sb_bar + NORTH_OFFSET, NORTH_SIZE);
	if (!north) {
		err = -ENOMEM;
		goto fail_pci;
	}
	reg0 = readl(north);
	padbar = readl(north + 0x0c);
	pr_info(DRV ": north window %pa+0x%lx: reg0=0x%08x padbar=0x%08x\n",
		&p2sb_bar, (unsigned long)NORTH_OFFSET, reg0, padbar);
	if (reg0 == 0xffffffff || padbar >= NORTH_SIZE) {
		pr_err(DRV ": north window not decodable (P2SB MMIO disabled?)\n");
		err = -ENODEV;
		goto fail_unmap;
	}
	pads = north + padbar;
	pad_output(PIN_MDC, 0);
	pad_input(PIN_MDIO);

	edge_bus = mdiobus_alloc();
	if (!edge_bus) {
		err = -ENOMEM;
		goto fail_unmap;
	}
	edge_bus->name = "VMware Edge 610 relocated MDIO";
	strscpy(edge_bus->id, "sw0", MII_BUS_ID_SIZE);
	edge_bus->parent = host;
	edge_bus->read = edge610_mdio_read;
	edge_bus->write = edge610_mdio_write;
	edge_bus->phy_mask = ~0U;

	err = mdiobus_register(edge_bus);
	if (err)
		goto fail_bus;

	memset(&switch_pdata, 0, sizeof(switch_pdata));
	switch_pdata.compatible = "marvell,mv88e6190";
	switch_pdata.enabled_ports = GENMASK(6, 1) | BIT(cpu_port);
	switch_pdata.netdev = conduit;
	switch_pdata.irq = 0;
	switch_pdata.cd.host_dev = host;
	switch_pdata.cd.sw_addr = 0;
	/* OpenWrt DSA naming: user ports are lan1..lan6 (CVMagic upstream
	 * used ge1..ge6; renamed to match this image's network config and
	 * the delivery checklist).
	 */
	switch_pdata.cd.port_names[1] = "lan1";
	switch_pdata.cd.port_names[2] = "lan2";
	switch_pdata.cd.port_names[3] = "lan3";
	switch_pdata.cd.port_names[4] = "lan4";
	switch_pdata.cd.port_names[5] = "lan5";
	switch_pdata.cd.port_names[6] = "lan6";
	switch_pdata.cd.port_names[cpu_port] = "cpu";

	switch_mdio = mdio_device_create(edge_bus, 0);
	if (IS_ERR(switch_mdio)) {
		err = PTR_ERR(switch_mdio);
		switch_mdio = NULL;
		goto fail_mdiobus;
	}
	strscpy(switch_mdio->modalias, "mv88e6085", MDIO_NAME_SIZE);
	switch_mdio->bus_match = edge610_mdio_bus_match;
	switch_mdio->dev.platform_data = &switch_pdata;
	err = mdio_device_register(switch_mdio);
	if (err)
		goto fail_mdiodev;
	if (!switch_mdio->dev.driver) {
		err = -ENODEV;
		goto fail_registered_mdiodev;
	}

	if (force_cpu_phyctl >= 0)
		mdiobus_write(edge_bus, cpu_port, 1, force_cpu_phyctl);
	if (force_cpu_ctl0 >= 0)
		mdiobus_write(edge_bus, cpu_port, 4, force_cpu_ctl0);
	if (force_cpu_map >= 0)
		mdiobus_write(edge_bus, cpu_port, 6, force_cpu_map);

	for (port = 1; port <= 10; port++) {
		if (port > 6 && port != cpu_port)
			continue;
		value = mdiobus_read(edge_bus, port, 4);
		pr_info(DRV ": p%d status=0x%04x phyctl=0x%04x ctl0=0x%04x map=0x%04x ctl2=0x%04x etype=0x%04x\n",
			port,
			mdiobus_read(edge_bus, port, 0),
			mdiobus_read(edge_bus, port, 1), value,
			mdiobus_read(edge_bus, port, 6),
			mdiobus_read(edge_bus, port, 8),
			mdiobus_read(edge_bus, port, 15));
	}

	pr_info(DRV ": registered 88E6190 on sw0, ports lan1-lan6, CPU port %u via %s\n",
		cpu_port,
		conduit_name);
	return 0;

fail_registered_mdiodev:
	mdio_device_remove(switch_mdio);
fail_mdiodev:
	mdio_device_free(switch_mdio);
	switch_mdio = NULL;
fail_mdiobus:
	mdiobus_unregister(edge_bus);
fail_bus:
	mdiobus_free(edge_bus);
	edge_bus = NULL;
fail_unmap:
	iounmap(north);
	north = NULL;
fail_pci:
	pci_dev_put(p2sb);
	p2sb = NULL;
fail_netdev:
	dev_put(conduit);
	conduit = NULL;
	return err;
}

static void __exit edge610_dsa_exit(void)
{
	if (switch_mdio) {
		mdio_device_remove(switch_mdio);
		mdio_device_free(switch_mdio);
	}
	if (edge_bus) {
		mdiobus_unregister(edge_bus);
		mdiobus_free(edge_bus);
	}
	if (north)
		iounmap(north);
	if (p2sb)
		pci_dev_put(p2sb);
	if (conduit)
		dev_put(conduit);
	pr_info(DRV ": unregistered DSA board topology\n");
}

module_init(edge610_dsa_init);
module_exit(edge610_dsa_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("VMware Edge 610 DSA board registration for Marvell 88E6190");
MODULE_SOFTDEP("pre: mv88e6xxx");
