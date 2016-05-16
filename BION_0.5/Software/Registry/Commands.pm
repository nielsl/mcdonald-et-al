package Software::Registry::Commands;            # -*- perl -*-

# Returns a list of all user commands. 

use strict;
use warnings FATAL => qw ( all );

my ( @descriptions );

# Installation and uninstallation,

push @descriptions, (
    {
        "title" => "Main software installer",
        "name" => "install_software",
        "datatype" => "soft_install",
    },{
        "title" => "Install pre-defined projects",
        "name" => "install_projects",
        "datatype" => "soft_install",
    },{
        "title" => "Install individual perl modules",
        "name" => "install_perlmods",
        "datatype" => "soft_install",
    },{
        "title" => "Install individual utility packages",
        "name" => "install_utilities",
        "datatype" => "soft_install"
    },{
        "title" => "Install individual analysis packages",
        "name" => "install_analyses",
        "datatype" => "soft_install",
    },{
        "title" => "Install individual datasets",
        "name" => "install_data",
        "datatype" => "soft_install",
    },{
        "title" => "Main software uninstaller",
        "name" => "uninstall_software",
        "datatype" => "soft_install",
    },{
        "title" => "Uninstall pre-defined projects",
        "name" => "uninstall_projects",
        "datatype" => "soft_install",
    },{
        "title" => "Uninstall individual utility packages",
        "name" => "uninstall_utilities",
        "datatype" => "soft_install"
    },{
        "title" => "Uninstall individual analysis packages",
        "name" => "uninstall_analyses",
        "datatype" => "soft_install",
    },{
        "title" => "Uninstall individual datasets",
        "name" => "uninstall_data",
        "datatype" => "soft_install",
    });

# Administration,

push @descriptions, (
    {
        "title" => "Add a user account",
        "name" => "add_user",
        "datatype" => "soft_admin",
    },{
        "title" => "Remove a user account",
        "name" => "delete_user",
        "datatype" => "soft_admin",
    },{
        "title" => "Start the Apache web-server",
        "name" => "start_apache",
        "datatype" => "soft_admin",
    },{
        "title" => "Stop the Apache web-server",
        "name" => "stop_apache",
        "datatype" => "soft_admin",
    },{
        "title" => "Start the MySQL database server",
        "name" => "start_mysql",
        "datatype" => "soft_admin",
    },{
        "title" => "Stop the MySQL database server",
        "name" => "stop_mysql",
        "datatype" => "soft_admin",
    },{
        "title" => "Start the batch queue",
        "name" => "start_queue",
        "datatype" => "soft_admin",
    },{
        "title" => "Stop the batch queue",
        "name" => "stop_queue",
        "datatype" => "soft_admin",
    },{
        "title" => "Start all servers",
        "name" => "start_servers",
        "datatype" => "soft_admin",
    },{
        "title" => "Stop all servers but Apache",
        "name" => "stop_servers",
        "datatype" => "soft_admin",
    },{
        "title" => "Delete all .~ code files etc",
        "name" => "code_clean",
        "datatype" => "soft_admin",
    },{
        "title" => "Find words in code files",
        "name" => "code_grep",
        "datatype" => "soft_admin",
    },{
        "title" => "Replace strings in code files",
        "name" => "code_replace",
        "datatype" => "soft_admin",
    },{
        "title" => "Replace tabs in code files with blanks",
        "name" => "code_detab",
        "datatype" => "soft_admin",
    },{
        "title" => "Check registry consistency",
        "name" => "check_registry",
        "datatype" => "soft_admin",
    },{
        "title" => "Create software distributions",
        "name" => "create_distribution",
        "datatype" => "soft_admin",
    });

# List,

push @descriptions, (
    {
        "title" => "List registered projects",
        "name" => "list_projects",
        "datatype" => "soft_list",
    },{
        "title" => "List registered data packages",
        "name" => "list_datasets",
        "datatype" => "soft_list",
    },{
        "title" => "List registered software",
        "name" => "list_software",
        "datatype" => "soft_list",
    },{
        "title" => "List registered data features",
        "name" => "list_features",
        "datatype" => "soft_list",
    },{
        "title" => "List registered software methods",
        "name" => "list_methods",
        "datatype" => "soft_list",
    },{
        "title" => "List command line scripts",
        "name" => "list_commands",
        "datatype" => "soft_list",
    },{
        "title" => "List registered data types",
        "name" => "list_types",
        "datatype" => "soft_list",
    },{
        "title" => "List registered users",
        "name" => "list_users",
        "datatype" => "soft_list",
    });

# Cluster,

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    my ( $class,
         ) = @_;

    return wantarray ? @descriptions : \@descriptions ;
}    

1;

__END__
