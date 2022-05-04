$variable = @(EOT)
  This is a multiline
  heredoc string
  | EOT

# comment
$variable_with_interpolation = @("EOT")
  Another example
  ${variable}
  with
  ${variable}
  with interpolation
  | EOT

# comment
case fact('os.family') {
  # comment
  'debian': {
    # comment
    $greeting = @(EOT)
      Hello
      World
      | EOT
  }
}

file { 'name':
  'heredoc1' => @(EOT)
    Hello
    World
    | EOT
  'heredoc2' => @(EOT),
    Hello
    World
    | EOT
}

file { '/etc/redis.conf':
  ensure  => file,  # comment
  # owner   => 'nobody',
  content => Deferred('inline_epp', [@(TEMPLATE), { 'redis_pass' => Deferred('unwrap', [$redis_pass]) }]),
    bind 0.0.0.0
    save ""
    requirepass <%= $redis_pass %>
    | TEMPLATE
  require => Package['redis'],
  notify  => Service['redis'],
}
