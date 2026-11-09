#include <linux/module.h>
#include <linux/init.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/string.h>
#include <linux/delay.h>
#include <linux/pci.h>
#include <linux/bitops.h>

#define DRV "edge610-switch"
#define P2SB_DEVICE_ID 0x19dd
#define NORTH_OFFSET 0x00c20000
#define NORTH_SIZE 0x10000
#define NORTH_BAR_SIZE 0x1000000
#define PIN_RESET 1
#define PIN_MDC 33
#define PIN_MDIO 34

#define PADCFG0_TXSTATE BIT(0)
#define PADCFG0_RXSTATE BIT(1)
#define PADCFG0_TXDIS BIT(8)
#define PADCFG0_RXDIS BIT(9)
#define PADCFG0_PMODE GENMASK(12, 10)

#define PORT_MAC_CTL 0x01
#define PORT_SWITCH_ID 0x03
#define PORT_CTL0 0x04
#define PORT_BASE_VLAN 0x06
#define PORT_DEFAULT_VLAN 0x07
#define PORT_CTL2 0x08

#define PORT_STATE_MASK 0x0003
#define PORT_STATE_FORWARDING 0x0003
#define PORT_FRAME_MODE_MASK 0x0300
#define PORT_8021Q_MODE_MASK 0x0c00

#define GLOBAL2 0x1c
#define G2_SMI_CMD 0x18
#define G2_SMI_DATA 0x19
#define G2_BUSY 0x8000
#define G2_C45_WRITE_DATA 0x0400
#define G2_C45_READ_DATA 0x0c00
#define MDIO_MMD_PHYXS 4
#define SERDES_BMCR 0x2000
#define SERDES_BMSR 0x2001
#define SERDES_ADVERTISE 0x2004
#define SERDES_LPA 0x2005
#define SERDES_PHY_STATUS 0xa003
#define X553_NW_MNG_IF_SEL 0x11178

static void __iomem *north;
static void __iomem *pads;
static ushort cpu_mac_ctl = 0x303f;
module_param(cpu_mac_ctl, ushort, 0444);
MODULE_PARM_DESC(cpu_mac_ctl, "88E6190 port 10 MAC control value");
static bool serdes_autoneg;
module_param(serdes_autoneg, bool, 0444);
MODULE_PARM_DESC(serdes_autoneg, "Enable port 10 2.5GBASE-X PCS autonegotiation");
static ushort cpu_port = 10;
module_param(cpu_port, ushort, 0444);
MODULE_PARM_DESC(cpu_port, "88E6190 CPU port: 9 (alternate) or 10 (primary)");
static bool x553_sgmii;
module_param(x553_sgmii, bool, 0444);
MODULE_PARM_DESC(x553_sgmii, "Temporarily select X553 SGMII/1G mode");
static ushort x553_speed = 1000;
module_param(x553_speed, ushort, 0444);
MODULE_PARM_DESC(x553_speed, "X553 SGMII speed in Mbps: 1000 (default) or 2500");

static unsigned long p2sb_bar_addr;
module_param(p2sb_bar_addr, ulong, 0444);
MODULE_PARM_DESC(p2sb_bar_addr,
		 "P2SB MMIO BAR to use when the PCI function is hidden by BIOS (0 = autodetect)");

/* Some BIOSes hide the P2SB PCI function (00:1f.1, 8086:19dd) from the bus
 * scan while still reserving its MMIO window. There the ACPI resource
 * "INTC3000:00" covers exactly P2SB_BAR + NORTH_OFFSET, so the BAR can be
 * derived from /proc/iomem instead of PCI enumeration.
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

/* Resolve the P2SB BAR: enumerated device first, then explicit parameter,
 * then the ACPI iomem hint. */
static resource_size_t edge610_p2sb_bar(struct pci_dev **pdev)
{
	resource_size_t bar = 0;

	*pdev = pci_get_device(PCI_VENDOR_ID_INTEL, P2SB_DEVICE_ID, NULL);
	if (*pdev) {
		bar = pci_resource_start(*pdev, 0);
		return bar;
	}
	if (p2sb_bar_addr) {
		pr_info(DRV ": P2SB hidden by BIOS, BAR %pa from module param\n",
			&p2sb_bar_addr);
		return p2sb_bar_addr;
	}
	bar = p2sb_bar_from_iomem();
	if (bar)
		pr_info(DRV ": P2SB hidden by BIOS, BAR %pa from iomem\n", &bar);
	return bar;
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
	mdio_bit(0); mdio_bit(1); /* ST */
	if (write) {
		mdio_bit(0); mdio_bit(1); /* OP write */
	} else {
		mdio_bit(1); mdio_bit(0); /* OP read */
	}
	for (i = 4; i >= 0; i--)
		mdio_bit((phy >> i) & 1);
	for (i = 4; i >= 0; i--)
		mdio_bit((reg >> i) & 1);
}

static int smi_read(unsigned int phy, unsigned int reg, u16 *value)
{
	u16 raw = 0;
	int i, ack;

	mdio_header(phy, reg, false);
	(void)mdio_sample();
	ack = !mdio_sample();
	for (i = 15; i >= 0; i--)
		raw |= mdio_sample() << i;
	mdc(0);
	mdio_drive(1);
	if (!ack)
		return -EIO;

	/* This board's SMI data phase is observed one clock early; discard the
	 * released-bus tail bit. 0x3203 consequently decodes to ID 0x1901.
	 */
	*value = raw >> 1;
	return 0;
}

static void smi_write(unsigned int phy, unsigned int reg, u16 value)
{
	int i;

	mdio_header(phy, reg, true);
	mdio_bit(1); mdio_bit(0); /* TA */
	for (i = 15; i >= 0; i--)
		mdio_bit((value >> i) & 1);
	mdc(0);
	mdio_drive(1);
}

static int port_update(int port, int reg, u16 clear, u16 set)
{
	u16 old, verify;
	int err;

	err = smi_read(port, reg, &old);
	if (err)
		return err;
	smi_write(port, reg, (old & ~clear) | set);
	err = smi_read(port, reg, &verify);
	if (err)
		return err;
	pr_info(DRV ": p%d r%02x 0x%04x -> 0x%04x\n",
		port, reg, old, verify);
	return 0;
}

static int g2_wait(void)
{
	u16 value;
	int i, err;

	for (i = 0; i < 100; i++) {
		err = smi_read(GLOBAL2, G2_SMI_CMD, &value);
		if (err)
			return err;
		if (!(value & G2_BUSY))
			return 0;
		udelay(100);
	}
	return -ETIMEDOUT;
}

static int serdes_c45_addr(u16 port, u16 reg)
{
	int err = g2_wait();

	if (err)
		return err;
	smi_write(GLOBAL2, G2_SMI_DATA, reg);
	smi_write(GLOBAL2, G2_SMI_CMD,
		  G2_BUSY | (port << 5) | MDIO_MMD_PHYXS);
	return g2_wait();
}

static int serdes_read(u16 port, u16 reg, u16 *value)
{
	int err = serdes_c45_addr(port, reg);

	if (err)
		return err;
	smi_write(GLOBAL2, G2_SMI_CMD,
		  G2_BUSY | G2_C45_READ_DATA |
		  (port << 5) | MDIO_MMD_PHYXS);
	err = g2_wait();
	if (err)
		return err;
	return smi_read(GLOBAL2, G2_SMI_DATA, value);
}

static int serdes_write(u16 port, u16 reg, u16 value)
{
	int err = serdes_c45_addr(port, reg);

	if (err)
		return err;
	smi_write(GLOBAL2, G2_SMI_DATA, value);
	smi_write(GLOBAL2, G2_SMI_CMD,
		  G2_BUSY | G2_C45_WRITE_DATA |
		  (port << 5) | MDIO_MMD_PHYXS);
	return g2_wait();
}

/* Put one X553 function into the board's SGMII/1G mode. Both functions are
 * configured when cpu_port=0 so the wiring difference between board
 * revisions (port 9 -> fn1, port 10 -> fn0) does not matter: whichever
 * pair is actually wired comes up and the init script picks it.
 */
static int x553_select_sgmii(unsigned int fn)
{
	struct pci_dev *dev;
	void __iomem *bar;
	u32 nwsel, new_nwsel;

	dev = pci_get_domain_bus_and_slot(0, 3, PCI_DEVFN(0, fn));
	if (!dev)
		return -ENODEV;
	bar = pci_iomap(dev, 0, 0);
	if (!bar) {
		pci_dev_put(dev);
		return -ENOMEM;
	}
	nwsel = readl(bar + X553_NW_MNG_IF_SEL);
	/* NW_MNG_IF_SEL speed field: BIT(19)=1G, BIT(20)=2.5G, BIT(21)=10G */
	new_nwsel = (nwsel & ~GENMASK(21, 17)) |
		    (x553_speed == 2500 ? BIT(20) : BIT(19)) | BIT(25);
	writel(new_nwsel, bar + X553_NW_MNG_IF_SEL);
	readl(bar + X553_NW_MNG_IF_SEL);
	pci_iounmap(dev, bar);
	pci_dev_put(dev);
	pr_info(DRV ": X553 fn%u NW_MNG_IF_SEL 0x%08x -> 0x%08x (speed %u)\n",
		fn, nwsel, new_nwsel, x553_speed);
	return 0;
}

static int __init edge610_switch_init(void)
{
	struct pci_dev *p2sb;
	resource_size_t p2sb_bar;
	u32 padbar, reg0;
	u16 id, status;
	int port, err;

	p2sb_bar = edge610_p2sb_bar(&p2sb);
	pci_dev_put(p2sb);
	p2sb = NULL;
	if (!p2sb_bar) {
		pr_err(DRV ": P2SB BAR unavailable (device hidden by BIOS and no iomem hint); pass p2sb_bar_addr=\n");
		return -ENODEV;
	}

	north = ioremap(p2sb_bar + NORTH_OFFSET, NORTH_SIZE);
	if (!north)
		return -ENOMEM;
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
	if (cpu_port != 0 && cpu_port != 9 && cpu_port != 10) {
		err = -EINVAL;
		goto fail_unmap;
	}

	pad_output(PIN_MDC, 0);
	pad_input(PIN_MDIO);
	pad_output(PIN_RESET, 0);
	msleep(100);
	pad_output(PIN_RESET, 1);
	msleep(500);

	err = smi_read(0, PORT_SWITCH_ID, &id);
	if (err || (id & 0xfff0) != 0x1900) {
		pr_err(DRV ": unexpected switch ID 0x%04x (err=%d)\n", id, err);
		err = -ENODEV;
		goto fail_unmap;
	}
	pr_info(DRV ": Marvell 88E6190 rev %u at P2SB BAR %pa\n",
		id & 0xf, &p2sb_bar);

	if (x553_sgmii) {
		if (cpu_port) {
			err = x553_select_sgmii(cpu_port == 10 ? 0 : 1);
			if (err)
				goto fail_unmap;
			port_update(cpu_port, 0, 0x000f, 0x000a); /* SGMII C_Mode */
		} else {
			x553_select_sgmii(0);
			x553_select_sgmii(1);
			port_update(9, 0, 0x000f, 0x000a);
			port_update(10, 0, 0x000f, 0x000a);
		}
	}

	/* Isolate each front-panel port to the CPU port(s). With cpu_port=0
	 * both CPU ports are enabled and the front panels join VLANs 1..6,
	 * which both CPU ports are members of.
	 */
	for (port = 1; port <= 6; port++) {
		err = port_update(port, PORT_BASE_VLAN, 0x07ff,
				  cpu_port ? BIT(cpu_port) : GENMASK(6, 1));
		if (err)
			goto fail_unmap;
		port_update(port, PORT_DEFAULT_VLAN, 0x0fff, 1);
		port_update(port, PORT_CTL2, PORT_8021Q_MODE_MASK, 0);
		port_update(port, PORT_CTL0,
			    PORT_FRAME_MODE_MASK | PORT_STATE_MASK,
			    PORT_STATE_FORWARDING);
	}

	/* CPU port: normal untagged frames, 2.5 Gbit full duplex, link forced up.
	 * The X553 function advertises only 2500baseT/Full on this board. For the
	 * 6390 family, 2.5G is ForceSpeed + AltSpeed + speed value 3.
	 */
	{
		int cports[2] = { 9, 10 };
		int i, n = cpu_port ? 1 : 2;

		if (cpu_port)
			cports[0] = cpu_port;

		for (i = 0; i < n; i++) {
			port_update(cports[i], PORT_BASE_VLAN, 0x07ff,
				    GENMASK(6, 1));
			port_update(cports[i], PORT_DEFAULT_VLAN, 0x0fff, 1);
			port_update(cports[i], PORT_CTL2,
				    PORT_8021Q_MODE_MASK, 0);
			port_update(cports[i], PORT_CTL0,
				    PORT_FRAME_MODE_MASK | PORT_STATE_MASK,
				    PORT_STATE_FORWARDING);
			port_update(cports[i], PORT_MAC_CTL, 0xffff,
				    cpu_mac_ctl);
		}
	}

	/* Power the 2.5GBASE-X PCS and advertise full duplex with symmetric pause.
	 * Enabling AN triggers negotiation with the X553 link partner.
	 */
	{
		int cports[2] = { 9, 10 };
		int i, n = cpu_port ? 1 : 2;

		if (cpu_port)
			cports[0] = cpu_port;

		for (i = 0; i < n; i++) {
			u16 sp = cports[i];

			if (serdes_read(sp, SERDES_BMCR, &status))
				continue;
			pr_info(DRV ": serdes%d BMCR before=0x%04x\n", sp, status);
			status &= ~(BIT(15) | BIT(14) | BIT(11));
			if (serdes_autoneg)
				status |= BIT(12) | BIT(9);
			else
				status &= ~(BIT(12) | BIT(9));
			serdes_write(sp, SERDES_ADVERTISE, 0x00e0);
			serdes_write(sp, SERDES_BMCR, status);
			msleep(100);
			if (!serdes_read(sp, SERDES_BMCR, &status))
				pr_info(DRV ": serdes%d BMCR after=0x%04x\n",
					sp, status);
			if (!serdes_read(sp, SERDES_BMSR, &status))
				pr_info(DRV ": serdes%d BMSR=0x%04x\n", sp, status);
			if (!serdes_read(sp, SERDES_LPA, &status))
				pr_info(DRV ": serdes%d LPA=0x%04x\n", sp, status);
			if (!serdes_read(sp, SERDES_PHY_STATUS, &status))
				pr_info(DRV ": serdes%d PHY status=0x%04x\n",
					sp, status);
		}
	}

	for (port = 1; port <= 6; port++) {
		if (!smi_read(port, 0, &status))
			pr_info(DRV ": ge%d status=0x%04x link=%s\n", port,
				status, status & BIT(11) ? "up" : "down");
	}
	{
		int cports[2] = { 9, 10 };
		int i, n = cpu_port ? 1 : 2;

		if (cpu_port)
			cports[0] = cpu_port;
		for (i = 0; i < n; i++) {
			if (!smi_read(cports[i], 0, &status))
				pr_info(DRV ": cpu%d status=0x%04x link=%s\n",
					cports[i], status,
					status & BIT(11) ? "up" : "down");
		}
	}

	return 0;

fail_unmap:
	iounmap(north);
	north = NULL;
	return err;
}

static void __exit edge610_switch_exit(void)
{
	int port;

	for (port = 1; port <= 6; port++)
		port_update(port, PORT_CTL0, PORT_STATE_MASK, 0);
	port_update(9, PORT_CTL0, PORT_STATE_MASK, 0);
	port_update(10, PORT_CTL0, PORT_STATE_MASK, 0);
	if (north)
		iounmap(north);
	pr_info(DRV ": front-panel and CPU ports disabled\n");
}

module_init(edge610_switch_init);
module_exit(edge610_switch_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("VMware Edge 610 Marvell 88E6190 standalone switch setup");
