# == Define: ciwatch::initd_service
#
# Creates initd service for an executable which can not run as daemon on its
# own.
define ciwatch::initd_service(
  $exec_cmd,
  $short_description,
  $runas_user,
  $ensure = undef,
  $service_name = $title,
) {

  # Template uses:
  # service_name
  # short_description
  # runas_user
  file { "/etc/init.d/${service_name}":
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => '0555',
    content => template('ciwatch/ciwatch_service.init.erb'),
  }

  if $ensure == undef {
    service { $service_name:
      enable     => true,
      hasrestart => true,
      require    => File["/etc/init.d/${service_name}"],
    }
  }
  else {
    service { $service_name:
      ensure     => $ensure,
      enable     => true,
      hasrestart => true,
      require    => File["/etc/init.d/${service_name}"],
    }
  }

}
