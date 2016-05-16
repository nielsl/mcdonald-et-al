package Software::Registry::Options;

# -*- perl -*-

# Returns a list of all software installation options. 
# Order matters, please dont change.

use strict;
use warnings FATAL => qw ( all );

my @descriptions =
    ({
        "title" => "Perl language",
        "name" => "perl",
        "datatype" => "soft_sys"
     },{
         "title" => "Third-party support utilities",
         "name" => "utilities",
         "datatype" => "soft_util"
     },{
         "title" => "GNU Awk language",
         "name" => "gawk",
         "datatype" => "soft_sys"
     },{
         "title" => "Python language",
         "name" => "python",
         "datatype" => "soft_sys"
     },{
         "title" => "Ruby language",
         "name" => "ruby",
         "datatype" => "soft_sys"
     },{
         "title" => "Third-party analysis utilities",
         "name" => "analyses",
         "datatype" => "soft_anal"
     },{
         "title" => "Apache www server",
         "name" => "apache",
         "datatype" => "soft_sys"
     # },{
     #     "title" => "MySQL database (MariaDB)",
     #     "name" => "mysql",
     #     "datatype" => "soft_sys"
     },{
         "title" => "Nano text editor",
         "name" => "nano",
         "datatype" => "soft_sys"
     });

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub descriptions
{
    my ( $class,
         ) = @_;

    return wantarray ? @descriptions : \@descriptions ;
}    

1;

__END__
