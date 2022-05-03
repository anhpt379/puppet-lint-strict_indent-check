$variable = @(EOT)
  This is a multiline
  heredoc string
  | EOT

$variable_with_interpolation = @("EOT")
  Another example
  ${variable}
  with
  ${variable}
  with interpolation
  | EOT

case fact('os.family') {
  'debian': {
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
