# Define a mon
#
define ceph::conf::mon (
  $mon_addr,
  $mon_port,
  $config = {},
) {
  validate_hash($config)

  @@concat::fragment { "ceph-mon-${name}.conf":
    target  => '/etc/ceph/ceph.conf',
    order   => '50',
    content => template('ceph/ceph.conf-mon.erb'),
  }

  @@ceph::add_mon { "cluster-${name}":
    mon_id   => $name,
    mon_addr => $mon_addr,
    mon_port => $mon_port,
  }

}
