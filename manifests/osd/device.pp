# Configure a ceph osd device
#
# == Namevar
# the resource name is the full path to the device to be used.
#
# == Dependencies
#
# none
#
# == Authors
#
#  François Charlier francois.charlier@enovance.com
#
# == Copyright
#
# Copyright 2013 eNovance <licensing@enovance.com>
#

define ceph::osd::device (
  $partition_table = true,
  $partition_table_type = gpt,
  $dmcrypt_device = false,
) {

  include ceph::osd
  include ceph::conf
  include ceph::params

  # $name should be full devices path, like /dev/sda
  # Replace everything before the last / so only the last element remains.
  # /dev/sda => sda
  $full_dev_path = $name
  $devname = regsubst($name, '.*/', '')


  if $partition_table == true {
    exec { "mktable_gpt_${devname}":
      command => "parted -a optimal --script ${full_dev_path} mktable ${partition_table_type}",
      unless  => "parted --script ${full_dev_path} print|grep -sq 'Partition Table: ${partition_table_type}'",
      require => Package['parted']
    }

    exec { "mkpart_${devname}":
      command => "parted -a optimal -s ${full_dev_path} mkpart ceph 0% 100%",
      unless  => "parted ${full_dev_path} print | egrep '^ 1.*ceph$'",
      require => [Package['parted'], Exec["mktable_gpt_${devname}"]]
    }

    if $dmcrypt_device == false {
      $dev_partition = "${full_dev_path}1"
      $devname_partition = "${devname}1"
      }
    elsif $dmcrypt_device == true {
        $dev_partition = "${full_dev_path}p1"
        $devname_partition = "${devname}p1"
      }

      exec { "mkfs_${devname}":
      command => "mkfs.xfs -f -d agcount=${::processorcount} -l size=1024m -n size=64k ${dev_partition}",
      unless  => "xfs_admin -l ${dev_partition}",
      require => [Package['xfsprogs']],
    }
  }
  elsif $partition_table == false {
    notify {"Value of partition_table in l64:${partition_table}": }
    $dev_partition = $full_dev_path
    exec { "mkfs_${devname}":
      command => "mkfs.xfs -f -d agcount=${::processorcount} -l size=1024m -n size=64k ${dev_partition}",
      unless  => "xfs_admin -l ${name}",
      require => [Package['xfsprogs']],
    }
  }

  $blkid_uuid_fact = "blkid_uuid_${devname_partition}"
  notify {"${blkid_uuid_fact}": }
  notify { "BLKID FACT ${devname_partition}: ${blkid_uuid_fact}": }
  $blkid = inline_template('<%= scope.lookupvar(blkid_uuid_fact) or "undefined" %>')
  notify { "BLKID ${devname_partition}: ${blkid}": }

  if $blkid != 'undefined' {
    exec { "ceph_osd_create_${devname}":
      command => "ceph osd create ${blkid}",
      unless  => "ceph osd dump | grep -sq ${blkid}",
      require => Ceph::Key['admin'],
    }

    $osd_id_fact = "ceph_osd_id_${devname_partition}"
    notify { "OSD ID FACT ${devname_partition}: ${osd_id_fact}": }
    $osd_id = inline_template('<%= scope.lookupvar(osd_id_fact) or "undefined" %>')
    notify { "OSD ID ${devname_partition}: ${osd_id}":}

    if $osd_id != 'undefined' {

      ceph::conf::osd { $osd_id:
        device       => $dev_partition,
        cluster_addr => $::ceph::osd::cluster_address,
        public_addr  => $::ceph::osd::public_address,
      }

      $osd_data = regsubst($::ceph::conf::osd_data, '\$id', $osd_id)

      file { $osd_data:
        ensure => directory,
      }

      mount { $osd_data:
        ensure  => mounted,
        device  => "${dev_partition}",
        atboot  => true,
        fstype  => 'xfs',
        options => 'rw,noatime,inode64',
        pass    => 2,
        require => [
          Exec["mkfs_${devname}"],
          File[$osd_data]
        ],
      }

      exec { "ceph-osd-mkfs-${osd_id}":
        command => "ceph-osd -c /etc/ceph/ceph.conf \
-i ${osd_id} \
--mkfs \
--mkkey \
--osd-uuid ${blkid}
",
        creates => "${osd_data}/keyring",
        require => [
          Mount[$osd_data],
          Concat['/etc/ceph/ceph.conf'],
          ],
      }

      exec { "ceph-osd-register-${osd_id}":
        command => "\
ceph auth add osd.${osd_id} osd 'allow *' mon 'allow rwx' \
-i ${osd_data}/keyring",
        require => Exec["ceph-osd-mkfs-${osd_id}"],
      }

      exec { "ceph-osd-crush-${osd_id}":
        command => "\
ceph osd crush set ${osd_id} 1 root=default host=${::hostname}",
        require => Exec["ceph-osd-register-${osd_id}"],
      }

      service { "ceph-osd.${osd_id}":
        ensure    => running,
        provider  => $::ceph::params::service_provider,
        start     => "service ceph start osd.${osd_id}",
        stop      => "service ceph stop osd.${osd_id}",
        status    => "service ceph status osd.${osd_id}",
        require   => Exec["ceph-osd-crush-${osd_id}"],
        subscribe => Concat['/etc/ceph/ceph.conf'],
      }

    }

  }

}
