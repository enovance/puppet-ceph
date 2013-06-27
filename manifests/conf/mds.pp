define ceph::conf::mds {
  @@concat::fragment { "ceph-mds-${name}.conf":
    target  => '/etc/ceph/ceph.conf',
    order   => '60',
    content => template('ceph/ceph.conf-mds.erb'),
  }
}
