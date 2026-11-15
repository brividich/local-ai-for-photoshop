@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                       # interactive installer: coloured console output is intended
        'PSUseShouldProcessForStateChangingFunctions', # -DryRun is the supported preview mode
        'PSUseSingularNouns',
        'PSAvoidUsingPositionalParameters'
    )
}
