#!/bin/bash
# bash <(wget -qO - https://pagespeedplus.github.io/ubuntu/home/skripte/install/initial-setup.sh) user
set -euo pipefail

########################
### SKRIPT VARIABLEN ###
########################

# Benutzer mit sudo Privilegien
USERNAME=$1

# Ein/Aus für kopieren der authorized_keys des Root-Benutzers auf den neuen sudo-Benutzer kopieren.
COPY_AUTHORIZED_KEYS_FROM_ROOT=true

# Additional Zusätzliche öffentliche Schlüssel, die dem neuen sudo-Benutzer hinzugefügt werden sollen.
# OTHER_PUBLIC_KEYS_TO_ADD=(
#     "ssh-rsa AAAAB..."
#     "ssh-rsa AAAAB..."
# )

OTHER_PUBLIC_KEYS_TO_ADD=(
      "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAB33mYUGa5qOmo4j5I/Gtsg/WOtoPhtZsfm97YHx1FWr3DJAROqWTpxvxdrmDefEQzmLYT7NfyfQGh7wv6LXP/iAwCTR9KP83SIhOEvUOEC/gpTHHucFmlK47suHRGzD/Ye/c9PVBjxbc/s7HYdjQDHoffmT5nbpt7PmBHecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBADj+tff/XWUx+AOlnIzjnUWf6ARcMmLyhl2IINXTAH6ypCrvmHAAY0jjf2vIKtjY1EygScXO3iH1NEVG4ZFKeFU1QFK63Jz0k4ZhEXo2Sf1vaE3CoXUAP+hl+rhbe9MsOa8kqglcwCXF42v7MSq4oCy4F/+e2HEGDAhTJj/2CpmxaHV6w== ecdsa-key-20200126wnRjogGYqFg=="
)

#####################
### SYSTEM KONFIG ###
#####################

# System Update
apt-get update && apt-get upgrade -y && apt-get autoremove --purge -y && apt-get clean

# Benötigte Tools installieren
apt-get -y install unattended-upgrades fail2ban ntp debconf-utils nano net-tools curl wget ufw git htop unzip

# Deutsche Sprache bereit stellen
apt-get -y install language-pack-de language-pack-de-base manpages-de

# Automatische Sicherheitsupdates aktivieren
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

# Bash als Standart Shell
echo "dash dash/sh boolean false" | debconf-set-selections
dpkg-reconfigure -f noninteractive dash

# NTP-Server aus Deutschland verwenden
wget -O /etc/ntp.conf https://pagespeedplus.github.io/ubuntu/etc/ntp.conf
systemctl restart ntp

###################
### USER KONFIG ###
###################

# sudo-Benutzer hinzufügen und Berechtigungen vergeben
useradd --create-home --shell "/bin/bash" --groups sudo "${USERNAME}"

# Überprüfen Sie, ob das Root-Konto ein richtiges Passwort hat.
encrypted_root_pw="$(grep root /etc/shadow | cut --delimiter=: --fields=2)"

if [ "${encrypted_root_pw}" != "*" ]; then
    # Transfer auto-generated root password to user if present and lock the root account to password-based access
    echo "${USERNAME}:${encrypted_root_pw}" | chpasswd --encrypted
    passwd --lock root
else
    # Löschen des ungültigen Passwort, wenn Schlüssel verwendet werden. Ein neues Passwort wird beim ersten Login gesetzt.
    passwd --delete "${USERNAME}"
fi

# Verfallen Sie das Passwort des sudo-Benutzers sofort, um eine Änderung zu erzwingen.
chage --lastday 0 "${USERNAME}"

# SSH-Verzeichnis für sudo-Benutzer erstellen
home_directory="$(eval echo ~${USERNAME})"
mkdir --parents "${home_directory}/.ssh"

# Kopiere authorized_keys von root
if [ "${COPY_AUTHORIZED_KEYS_FROM_ROOT}" = true ]; then
    cp /root/.ssh/authorized_keys "${home_directory}/.ssh"
fi

# Hinzufügen von zusätzlichen bereitgestellten öffentlichen Schlüsseln
for pub_key in "${OTHER_PUBLIC_KEYS_TO_ADD[@]}"; do
    echo "${pub_key}" >> "${home_directory}/.ssh/authorized_keys"
done

# SSH-Konfigurationseigentum und Berechtigungen anpassen
chmod 0700 "${home_directory}/.ssh"
chmod 0600 "${home_directory}/.ssh/authorized_keys"
chown --recursive "${USERNAME}":"${USERNAME}" "${home_directory}/.ssh"

# Root-SSH-Anmeldung mit Passwort deaktivieren
sed --in-place 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
if sshd -t -q; then
    systemctl restart sshd
fi

################
### NETZWERK ###
################

# Standart UFW Firewall Regeln
ufw logging low
ufw default allow outgoing
ufw default deny incoming
ufw allow 22

# UFW Firewall aktivieren
ufw --force enable

################
### SECURITY ###
################

# Download fail2ban Jail für ssh_custom_port
wget -O /etc/fail2ban/jail.d/defaults-debian.conf https://pagespeedplus.github.io/ubuntu/etc/fail2ban/jail.d/defaults-debian.conf
fail2ban-client reload && systemctl restart fail2ban.service

#################
### CUSTOMIZE ###
#################

# NANO Syntax Highlighting
# wget https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh -qO- | sh
reboot
