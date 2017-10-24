#
# Copyright 2017 (c) Andrey Galkin
#


class cfwebapp::redmine::gandi {
    # See https://www.redmine.org/issues/24864#change-81746

    file { '/usr/local/share/ca-certificates/GandiStandardSSLCA2.crt':
        content => file('cfwebapp/GandiStandardSSLCA2.pem'),
    }
    -> exec { 'Install GandiStandardSSLCA2':
        command => '/usr/sbin/update-ca-certificates',
        creates => '/etc/ssl/certs/GandiStandardSSLCA2.pem',
    }
}
