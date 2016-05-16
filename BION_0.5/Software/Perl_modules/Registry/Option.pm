package Registry::Option;                # -*- perl -*-

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> DESCRIPTION <<<<<<<<<<<<<<<<<<<<<<<<<<<<
#
# Module that defines get/setters and methods specific to registry 
# options. 
#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>><<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

use strict;
use warnings FATAL => qw ( all );

use Data::Dumper;

use Common::Config;
use Common::Messages;

use base qw ( Registry::Match Common::Option );

# >>>>>>>>>>>>>>>>>>>>>>>>> AUTOLOADED ROUTINES <<<<<<<<<<<<<<<<<<<<<<<<

# TODO: change this way of explicit declaration of accessors

my %Auto_get_setters = map { $_, 1 } qw 
    (
     id owner menus methods method path module schema tables columns 
     path format itypes itype otype iformat oformat features request
     dbfile dbtypes dbtype dbformats dbformat dbiformat dbitypes choices
     menu_2_opts imports skip_ids skip_features navigation 
     downloads download blastdbs citation files cid defaults hide_methods 
     hide_navigation colbeg colend display width maxlength cmdline
     def_viewer def_input def_request def_features is_active inputdb
     def_menu_1 def_menu_2 def_menu_3 window_height window_width ignore
     logo_link logo_image logo_text home_link merge_prefix infile outfile 
     css style header_style footer_style merge exports split_src baseurl 
     folder filexp compare datadir dirpath in_regexp acc_number
     keywords name projpath dbnames dbname label title selected credits
     datatypes datatype datapath datapath_full url description bgtrans
     dataset datasets datasets_other formats format params src_name inst_name split_sids
     min_pix_per_row max_pix_per_row min_pix_per_col max_pix_per_col
     routine max_score min_score selectable source visible values value
     min_entries types dbinputs iformats methods_menu datasets_menu
     administrator first_name last_name department e_mail telephone
     remote local post_commands depth org_taxon optional
     mol_name db_ids org_name hdr_fields hdr_regexp seq_id
     divide_regex divide_files trans header
     );

sub AUTOLOAD
{
    # Niels Larsen, March 2007.

    my ( $self,
         $value,
         ) = @_;

    my ( $method, $id );

    our $AUTOLOAD =~ /::(\w+)$/ and $method = $1;

    if ( $Auto_get_setters{ $method } )
    {
        if ( defined $value )
        {
              return $self->{ $method } = $value;
          }
        elsif ( exists $self->{ $method } )
        {
              return $self->{ $method };
          }
        else {
            return;
        }
    }
    elsif ( $method ne "DESTROY")
    {
        $method = "SUPER::$method";
        
        no strict "refs";
        return eval { $self->$method( $value ) };

#        &error( qq (Wrong looking method -> "$method") );
    }

    return;
}

sub new
{
    my ( $class,
         %args,
         ) = @_;

    my ( $self, $key );

    $self = {}; # $class->SUPER::new();

    $class = ( ref $class ) || $class;
    bless $self, $class;
    
    foreach $key ( keys %args )
    {
        if ( $Auto_get_setters{ $key } ) {
            $self->{ $key } = $args{ $key };
        } else {
            &error( qq (Wrong looking key -> "$key") );
        }
    }

    return $self;
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>> METHODS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

sub def_params
{
    my ( $self,
         ) = @_;

    my ( %params );

    %params = map { $_->[0], $_->[1] } @{ $self->params };

    return wantarray ? %params : \%params;
}

sub is_local_db
{
    # Niels Larsen, January 2007.

    # Returns true if a database is local (by simply checking if the 
    # datadir field is set), otherwise nothing.
    
    my ( $self,          # 
         ) = @_;

    # Returns 1 or nothing.

    if ( $self->datadir ) {
        return 1;
    } else {
        return;
    }
}
    
sub is_remote_db
{
    # Niels Larsen, January 2007.

    # Returns true if a database is a local otherwise nothing.
    
    my ( $self,          # 
         ) = @_;

    # Returns 1 or nothing.
    
    if ( $self->is_local_db ) {
        return;
    } else {
        return 1;
    }
}

sub inst_dir
{
    my ( $self,
        ) = @_;

    my ( $type, $dir, $name );

    $type = $self->datatype;
    $name = $self->inst_name;

    if ( $type eq "soft_sys" ) {
        $dir = "$Common::Config::pki_dir/$name";
    } elsif ( $type eq "soft_util" ) {
        $dir = "$Common::Config::uti_dir/$name";
    } elsif ( $type eq "soft_anal" ) {
        $dir = "$Common::Config::ani_dir/$name";
    } elsif ( $type eq "soft_perl_module" ) {
        $dir = "$Common::Config::pemi_dir/$name";
    } else {
        &error( qq (Wrong looking datatype -> "$type") );
    }

    return $dir;
}

sub logi_dir
{
    my ( $self,
        ) = @_;

    my ( $type, $dir, $name );

    $type = $self->datatype;
    $name = $self->inst_name;

    if ( $type eq "soft_sys" ) {
        $dir = "$Common::Config::logi_dir/$name";
    } elsif ( $type eq "soft_util" ) {
        $dir = "$Common::Config::logi_util_dir/$name";
    } elsif ( $type eq "soft_anal" ) {
        $dir = "$Common::Config::logi_anal_dir/$name";
    } elsif ( $type eq "soft_perl_module" ) {
        $dir = "$Common::Config::logi_pems_dir/$name";
    } else {
        &error( qq (Wrong looking datatype -> "$type") );
    }

    return $dir;
}

sub src_dir
{
    my ( $self,
        ) = @_;

    my ( $type, $dir, $name );

    $type = $self->datatype;
    $name = $self->src_name;

    if ( $type eq "soft_sys" ) {
        $dir = "$Common::Config::pks_dir/$name";
    } elsif ( $type eq "soft_util" ) {
        $dir = "$Common::Config::uts_dir/$name";
    } elsif ( $type eq "soft_anal" ) {
        $dir = "$Common::Config::ans_dir/$name";
    } elsif ( $type eq "soft_perl_module" ) {
        $dir = "$Common::Config::pems_dir/$name";
    } else {
        &error( qq (Wrong looking datatype -> "$type") );
    }

    return $dir;
}


1;

__END__

# sub params
# {
#     my ( $self,
#          $value,
#          ) = @_;
    
#     if ( defined $value )
#     {
#         local $Data::Dumper::Terse = 1;     # avoids variable names
#         local $Data::Dumper::Indent = 1;    # mild indentation
    
#         &dump( $value );
#         $self->{"params"} = Dumper( $value );

#         return $self;
#     }
#     else
#     {
#         $value = eval { $self->{"params"} };

#         return $value;
#     }

#     return;
# }
        
