#!/bin/bash

# Script para configurar un servidor de correo en Debian 12 con Postfix, Dovecot, Maildir y Rainloop
set -e

# Solicitar información al usuario
echo "Configuración de servidor de correo en Debian 12"
read -p "Ingresa tu dominio de correo (ejemplo: example.com): " MAIL_DOMAIN
read -p "Ingresa tu correo de prueba (ejemplo: user@example.com): " MAIL_USER
read -p "Ingresa la contraseña para el correo de prueba: " MAIL_PASS
read -p "Ingresa el directorio para instalar Rainloop (predeterminado: /var/www/html/rainloop): " RAINLOOP_DIR
RAINLOOP_DIR=${RAINLOOP_DIR:-/var/www/html/rainloop}

RAINLOOP_URL="https://www.rainloop.net/release/latest.zip"

# Actualizar repositorios e instalar paquetes necesarios
echo "Actualizando repositorios e instalando paquetes necesarios..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y postfix dovecot-core dovecot-imapd dovecot-pop3d \
                    apache2 php php-cli php-mbstring unzip curl ufw

# Configurar Postfix
echo "Configurando Postfix..."
sudo debconf-set-selections <<< "postfix postfix/mailname string $MAIL_DOMAIN"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
sudo apt install -y postfix

# Configuración de Postfix
sudo postconf -e "home_mailbox = Maildir/"
sudo postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
sudo postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
sudo postconf -e "inet_interfaces = all"
sudo postconf -e "inet_protocols = ipv4"

# Configurar alias virtual en Postfix
echo "$MAIL_USER $MAIL_USER" | sudo tee -a /etc/postfix/virtual
sudo postmap /etc/postfix/virtual
sudo systemctl restart postfix

# Configurar Dovecot
echo "Configurando Dovecot..."
sudo sed -i 's|#mail_location =|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
sudo sed -i 's|#disable_plaintext_auth = yes|disable_plaintext_auth = no|' /etc/dovecot/conf.d/10-auth.conf
sudo sed -i 's|auth_mechanisms = plain|auth_mechanisms = plain login|' /etc/dovecot/conf.d/10-auth.conf
sudo sed -i 's|ssl = required|ssl = no|' /etc/dovecot/conf.d/10-ssl.conf

# Reiniciar servicios
sudo systemctl restart dovecot
sudo systemctl restart postfix

# Crear usuario de correo
echo "Creando usuario de correo..."
sudo useradd -m -s /bin/false $(echo "$MAIL_USER" | cut -d'@' -f1)
echo "$(echo "$MAIL_USER" | cut -d'@' -f1):$MAIL_PASS" | sudo chpasswd

# Configurar Rainloop
echo "Instalando Rainloop..."
sudo mkdir -p "$RAINLOOP_DIR"
sudo curl -L "$RAINLOOP_URL" -o /tmp/rainloop.zip
sudo unzip /tmp/rainloop.zip -d "$RAINLOOP_DIR"
sudo chown -R www-data:www-data "$RAINLOOP_DIR"
sudo rm /tmp/rainloop.zip

# Configurar Apache para Rainloop
echo "Configurando Apache para Rainloop..."
RAINLOOP_CONF="/etc/apache2/sites-available/rainloop.conf"
sudo bash -c "cat > $RAINLOOP_CONF" <<EOL
<VirtualHost *:80>
    ServerName $MAIL_DOMAIN
    DocumentRoot $RAINLOOP_DIR

    <Directory $RAINLOOP_DIR>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL
sudo a2ensite rainloop
sudo systemctl reload apache2

# Configurar firewall UFW
echo "Configurando el firewall UFW..."
sudo ufw allow "OpenSSH"
sudo ufw allow "Apache Full"
sudo ufw allow 25
sudo ufw allow 143
sudo ufw allow 110
sudo ufw allow 587
sudo ufw --force enable

# Finalización
echo "Configuración completada."
echo "Rainloop está instalado en: http://$MAIL_DOMAIN"
echo "Usuario de prueba: $MAIL_USER"
echo "Por favor, accede a Rainloop y configura el servidor IMAP/SMTP manualmente."
