function Init {
  if ($Hostname) {
    $name = "$Hostname"
  } else {
    $name = (Get-WmiObject win32_computersystem).DNSHostName +
      "." +
      (Get-WmiObject win32_computersystem).Domain
  }

  $script:dataPath = "$PSScriptRoot\..\data"

  Write-HeaderLine "Setting up workstation '$name'"

  Ensure-AdministratorPrivileges
}

function Set-Hostname {
  if (-not $Hostname) {
    return
  }

  # TODO fn: implement!
  Write-Output "Set-Hostname not implemented yet"
}

function Init-PackageSystem {
  Write-HeaderLine "Setting up package system"

  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    $env:chocolateyUseWindowsCompression = 'true'
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol =
      [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).
      DownloadString('https://chocolatey.org/install.ps1'))
  }
}

function Update-System {
  Write-HeaderLine "Applying system updates"

  if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-PackageProvider -Name NuGet -Force
    Install-Module PSWindowsUpdate -Force
  }

  # TODO fn: stop this from blocking
  # Get-WUInstall -AcceptAll -AutoReboot -Verbose
}

function Install-BasePackages {
  Write-HeaderLine "Installing base packages"
  Install-PkgsFromJson "$dataPath\windows_base_pkgs.json"

  if (-not (Get-Module -ListAvailable -Name posh-git)) {
    Install-Module posh-git -Force
  }
}

function Set-Preferences {
  Write-HeaderLine "Setting preferences"

  # TODO fn: implement!
  Write-Host "Set-Preferences not implemented yet"
}

function Install-SSH {
  Write-HeaderLine "Setting up SSH"

  if (-not (Test-Path $env:SystemDrive\Windows\System32\OpenSSH)) {
    Write-InfoLine "Installing OpenSSH.Client"
    Add-WindowsCapability -Online -Name OpenSSH.Client*
    Write-InfoLine "Installing OpenSSH.Client"
    Add-WindowsCapability -Online -Name OpenSSH.Server*

    Write-InfoLine "Starting and enabling sshd service"
    Start-Service -Name sshd
    Set-Service -Name sshd -StartupType 'Automatic'

    Write-InfoLine "Setting default shell to PowerShell for OpenSSH"
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
      -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
      -PropertyType String -Force
  }
}

function Install-HeadlessPackages {
  Write-HeaderLine "Installing headless packages"
  Install-PkgsFromJson "$dataPath\windows_headless_pkgs.json"

  $wslstate = (Get-WindowsOptionalFeature -Online `
    -FeatureName Microsoft-Windows-Subsystem-Linux).State

  # Install Windows Subsystem for Linux if it is disabled
  if ($wslstate -eq "Disabled") {
    Write-InfoLine "Installing 'Microsoft-Windows-Subsystem-Linux'"
    Enable-WindowsOptionalFeature -Online `
      -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
  }

  $wsldistro = "wsl-ubuntu-1804"
  $wslroot = "$env:SystemDrive\Distros"
  $wsldst = "$wslroot\$wsldistro"

  # Download and install the Linux distribution if not found
  if (-not (Test-Path "$wsldst")) {
    $wslzip = "$env:TEMP\$wsldistro.zip"

    Write-InfoLine "Downloading '$wsldistro'"
    # Disable download progress bar which slows the download
    $ProgressPreference = 'silentlyContinue'
    Invoke-WebRequest -Uri "https://aka.ms/$wsldistro" `
      -OutFile "$wslzip" -UseBasicParsing
    $ProgressPreference = 'Continue'
    if (-not (Test-Path "$wslroot")) {
      New-Item -ItemType directory -Path "$wslroot"
    }
    Write-InfoLine "Extracting '$wsldistro' into $wsldst"
    Expand-Archive "$wslzip" "$wsldst"
    Remove-Item "$wslzip"
  }
}

function Install-Rust {
  $cargo_home = "$env:USERPROFILE\.cargo"
  $rustup = "$cargo_home\bin\rustup.exe"
  $cargo = "$cargo_home\bin\cargo.exe"

  Write-HeaderLine "Setting up Rust"

  if (-not (Test-Path "$rustup")) {
    Write-InfoLine "Installing Rust"
    & ([scriptblock]::Create((New-Object System.Net.WebClient).DownloadString(
      'https://gist.github.com/fnichol/699d3c2930649a9932f71bab8a315b31/raw/rustup-init.ps1')
      )) -y --default-toolchain stable
  }

  & "$rustup" self update
  & "$rustup" update

  & "$rustup" component add rust-src
  & "$rustup" component add rustfmt

  $plugins = Get-Content "$dataPath\rust_cargo_plugins.json" `
    | ConvertFrom-Json
  foreach ($plugin in $plugins) {
    if (-not (& "$cargo" install --list | Select-String -Pattern "$plugin")) {
      Write-InfoLine "Installing $plugin"
      & "$cargo" install --verbose "$plugin"
    }
  }
}

function Install-Ruby {
  Write-HeaderLine "Setting up Ruby"
  Install-Package "ruby"
}

function Install-Go {
  Write-HeaderLine "Setting up Go"
  Install-Package "golang"
}

function Install-Node {
  Write-HeaderLine "Setting up Node"
  Install-Package "nodejs-lts"
}

function Install-GraphicalPackages {
  Write-HeaderLine "Installing graphical packages"
  Install-PkgsFromJson "$dataPath\windows_graphical_pkgs.json"
}

function Finish {
  Write-HeaderLine "Finished setting up workstation, enjoy!"
}

function Install-PkgsFromJson($Json) {
  $pkgs = Get-Content "$Json" | ConvertFrom-Json

  foreach ($pkg in $pkgs) {
    Install-Package "$pkg"
  }
}

function Install-Package($Pkg) {
  $installed = @(
    @(choco list --limit-output --local-only) |
      ForEach-Object { $_.split('|')[0] }
  )

  if ($installed -contains "$Pkg") {
    return
  }

  Write-InfoLine "Installing package '$Pkg'"
  choco install -y "$Pkg"
}
