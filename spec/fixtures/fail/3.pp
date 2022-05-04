class test_comment (
) {
  file { 'name':
    ensure => present,
#    owner  => 'root',
    group  => 'root',
  }
}

