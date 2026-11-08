# serial-bridge.ps1 - expose a Windows COM port over TCP so a remote machine
# can drive the Edge 610 serial console (CP210x, 115200 8N1).
#
# Usage (on the PC that has the USB-serial cable attached):
#   1. close MobaXterm/PuTTY serial session (the COM port is exclusive)
#   2. powershell -ExecutionPolicy Bypass -File .\serial-bridge.ps1
#      (or: $env:EDGE610_COM="COM5"  to pick the port manually)
#   3. optional, to watch locally: MobaXterm -> Raw session -> 127.0.0.1:7001
#
# Firewall (once, elevated):
#   netsh advfirewall firewall add rule name="edge610-serial" dir=in action=allow protocol=TCP localport=7001

$Baud = 115200
$ListenPort = 7001
$ErrorActionPreference = "Stop"

$Port = $env:EDGE610_COM
if (-not $Port) {
    try {
        $dev = Get-CimInstance Win32_PnPEntity |
            Where-Object { $_.Name -match '\((COM\d+)\)' -and $_.Name -match 'CP210|Silicon|USB-SERIAL|CH34|FTDI' } |
            Select-Object -First 1
        if ($dev -and ($dev.Name -match '\((COM\d+)\)')) { $Port = $Matches[1] }
    } catch {}
}
if (-not $Port) {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    Write-Host ("No serial port detected. Ports seen: " + ($ports -join ","))
    Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.Name -match 'COM\d+' } |
        ForEach-Object { Write-Host ("  device: " + $_.Name) }
    Write-Host 'Set it manually first:  $env:EDGE610_COM="COM5"'
    exit 1
}

$sp = New-Object System.IO.Ports.SerialPort($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.ReadTimeout = 200
$sp.WriteTimeout = 500
try { $sp.Open() } catch {
    Write-Host ("cannot open " + $Port + ": " + $_.Exception.Message)
    exit 1
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $ListenPort)
$listener.Start()
$clients = New-Object System.Collections.ArrayList
$buf = New-Object byte[] 8192
Write-Host ("edge610 serial bridge: " + $Port + "@" + $Baud + "  <->  tcp " + $ListenPort + "   (Ctrl+C stops)")
Write-Host ("local watch: raw session to 127.0.0.1 port " + $ListenPort)

while ($true) {
    while ($listener.Pending()) {
        $c = $listener.AcceptTcpClient()
        $c.NoDelay = $true
        [void]$clients.Add($c)
        Write-Host ("client + " + $c.Client.RemoteEndPoint)
    }
    foreach ($c in @($clients)) {
        try {
            $st = $c.GetStream()
            while ($st.DataAvailable) {
                $n = $st.Read($buf, 0, $buf.Length)
                if ($n -le 0) { [void]$clients.Remove($c); $c.Close(); break }
                $sp.Write($buf, 0, $n)
            }
        } catch { [void]$clients.Remove($c); try { $c.Close() } catch {} }
    }
    if ($sp.BytesToRead -gt 0) {
        try { $n = $sp.Read($buf, 0, $buf.Length) } catch { $n = 0 }
        if ($n -gt 0) {
            foreach ($c in @($clients)) {
                try { $st = $c.GetStream(); $st.Write($buf, 0, $n); $st.Flush() }
                catch { [void]$clients.Remove($c); try { $c.Close() } catch {} }
            }
        }
    } else { Start-Sleep -Milliseconds 5 }
}
