# Each rule tests or emits a token from the same shell-native context parser.
function __zvm_next
    set -l requested $argv[1]
    set -l words (commandline -opc)
    set -l total (count $words)
    if test $total -eq 1
        test "$requested" = commands
        return
    end
    switch $words[2]
        case install
            set -l spec no
            set -l use no
            set -l no_zls no
            for token in $words[3..-1]
                switch "$token"
                    case --use
                        test "$use" = no; or return 1
                        set use yes
                    case --no-zls
                        test "$no_zls" = no; or return 1
                        set no_zls yes
                    case '-*' ''
                        return 1
                    case '*'
                        test "$spec" = no; or return 1
                        set spec yes
                end
            end
            switch "$requested"
                case installable
                    test "$spec" = no
                    return
                case use
                    test "$use" = no
                    return
                case no-zls
                    test "$no_zls" = no
                    return
            end
        case use
            test $total -eq 2; and test "$requested" = installed
            return
        case list
            test $total -eq 2; and test "$requested" = remote
            return
        case uninstall
            if test $total -eq 2
                contains -- "$requested" all inactive
                return
            else if test $total -eq 3; and test "$words[3]" = --all
                test "$requested" = yes
                return
            end
        case zls
            if test $total -eq 2
                test "$requested" = zls-install
                return
            else if test $total -eq 3; and test "$words[3]" = install
                test "$requested" = installed
                return
            end
    end
    return 1
end

complete -c zvm -f
complete -c zvm -n '__zvm_next commands' -a install -d 'Install Zig'
complete -c zvm -n '__zvm_next commands' -a use -d 'Select Zig offline'
complete -c zvm -n '__zvm_next commands' -a unset -d 'Clear selection'
complete -c zvm -n '__zvm_next commands' -a current -d 'Print selection'
complete -c zvm -n '__zvm_next commands' -a list -d 'List Zig builds'
complete -c zvm -n '__zvm_next commands' -a uninstall -d 'Remove toolchains'
complete -c zvm -n '__zvm_next commands' -a zls -d 'Manage ZLS'
complete -c zvm -n '__zvm_next commands' -a '--help' -d 'Show usage'
complete -c zvm -n '__zvm_next commands' -a '--version' -d 'Print manager version'
complete -c zvm -n '__zvm_next use' -a '--use' -d 'Select after install'
complete -c zvm -n '__zvm_next no-zls' -a '--no-zls' -d 'Skip ZLS'
complete -c zvm -n '__zvm_next installable' -a latest -d 'Newest stable Zig'
complete -c zvm -n '__zvm_next installable' -a master -d 'Current development build'
complete -c zvm -n '__zvm_next installable' -a '(zvm __complete installable 2>/dev/null)'
complete -c zvm -n '__zvm_next installed' -a '(zvm __complete installed 2>/dev/null)'
complete -c zvm -n '__zvm_next remote' -a '--remote' -d 'List platform builds'
complete -c zvm -n '__zvm_next all' -a '--all' -d 'Remove all managed versions'
complete -c zvm -n '__zvm_next yes' -a '--yes' -d 'Confirm removal'
complete -c zvm -n '__zvm_next inactive' -a '(zvm __complete inactive 2>/dev/null)'
complete -c zvm -n '__zvm_next zls-install' -a install -d 'Install compatible ZLS'
