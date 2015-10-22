# Copyright (c) 2015 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# == Class: ciwatch
#
# Deploy CI Watch monitoring dashboard.
#
# The dashboard consists of two services: gerrit listener (ciwatcher) and ui
# (ciwatch). The puppet module would not start these automatically and it is
# expected other means to be used.
# To manually start both:
#   service ciwatch start
#   service ciwatcher start
#
# Dashboard's UI would be accessible on port 5000 (flask's default).
#
# === Parameters
#
# [*gerrit_user*]
#   Gerrit user account to be used by gerrit listener.
#
# [*ssh_private_key*]
#   Contents of ssh private key. This key needs to be authorized to connect
#   to gerrit account.
#
# [*gerrit_hostname*]
#   Gerrit server to be used for ciwatch gerrit listener.
#
# [*gerrit_port*]
#   Gerrit server port, default 29418.
#
#
# === Examples
#
# class { '::ciwatch':
#   gerrit_user         => hiera('ciwatch::gerit_user'),
#   ssh_private_key     => hiera('ciwatch::ssh_private_key'),
#   mysql_password      => hiera('ciwatch::mysql_password'),
#   mysql_root_password => hiera('ciwatch::mysql_root_password'),
# }
#
class ciwatch (
  $gerrit_user,
  $ssh_private_key,
  $mysql_password,
  $mysql_root_password = undef,
  $setup_mysql = true,
  $gerrit_hostname = 'review.openstack.org',
  $gerrit_port = 29418,
) {

  user { 'ciwatch':
    ensure     => present,
    home       => '/home/ciwatch',
    shell      => '/bin/bash',
    gid        => 'ciwatch',
    managehome => true,
    require    => Group['ciwatch'],
  }
  group { 'ciwatch':
    ensure => present,
  }

  if $setup_mysql {
    class { '::ciwatch::mysql':
      mysql_password      => $mysql_password,
      mysql_root_password => $mysql_root_password,
    }
  }

  # mysql module can install python-mysql if $mysql::params::bindings_enable
  # set to true, but it also would pull in many other unnecessary dependencies.
  # So install the binding manually.
  package {'python-mysqldb':
    ensure => present,
  }

  vcsrepo { '/opt/ciwatch':
    ensure   => latest,
    provider => git,
    revision => 'master',
    source   => 'https://git.openstack.org/openstack-infra/ciwatch',
  }

  include ::pip
  exec { 'install_ciwatch' :
    provider    => 'shell',
    command     => 'pip install -U /opt/ciwatch',
    subscribe   => Vcsrepo['/opt/ciwatch'],
    refreshonly => true,
    require     => [
      Class['pip'],
      File['/etc/ciwatch/ciwatch.conf'],
      Package['python-mysqldb'],
    ],
  }

  $ssh_private_key_file = '/var/lib/ciwatch/ssh/id_rsa'

  file { '/etc/ciwatch/':
    ensure => directory,
  }
  # Template uses:
  # gerrit_user
  # ssh_private_key_file
  # gerrit_server
  # gerrit_port
  # mysql_password
  file { '/etc/ciwatch/ciwatch.conf':
    content => template('ciwatch/ciwatch.conf.erb'),
    require => File['/etc/ciwatch'],
  }

  file { [
    '/var/lib/ciwatch',
    '/var/lib/ciwatch/ssh',
  ]:
    ensure => directory,
    owner  => 'ciwatch',
    group  => 'ciwatch',
  }
  file { $ssh_private_key_file:
    owner   => 'ciwatch',
    group   => 'ciwatch',
    mode    => '0400',
    content => $ssh_private_key,
    require => File['/var/lib/ciwatch/ssh/'],
  }

  file { '/var/log/ciwatch':
    ensure  => directory,
    owner   => 'ciwatch',
    recurse => true,  # Ensure ownership is set for all logs
    require => User['ciwatch'],
  }

  ciwatch::initd_service { 'ciwatch':
    exec_cmd          => 'ciwatch-server',
    short_description => 'CI Watch Web UI',
    runas_user        => 'ciwatch',
    require           => Exec['install_ciwatch'],
  }

  ciwatch::initd_service { 'ciwatcher':
    exec_cmd          => 'ciwatch-stream-events',
    short_description => 'CI Watch Gerrit Event Listener',
    runas_user        => 'ciwatch',
    require           => Exec['install_ciwatch'],
  }

}
