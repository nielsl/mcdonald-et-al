package Words::Download;   # -*- perl -*- 

# Description of what the routines here have 
# in common.

use strict; 
use warnings FATAL => qw ( all );

use Common::Messages;

use Registry::Args;

use Common::HTTP;
use Common::File;
use Common::Tables;

# >>>>>>>>>>>>>>>>>>>>> ROUTINES AND METHODS <<<<<<<<<<<<<<<<<<<<<<<<

    
1;

__END__

# sub parse_edict_page
# {
#     # Niels Larsen, May 2009.

#     # NOT USED 

#     my ( $url,
#          $type,
#          ) = @_;

#     my ( $html, $line, @list );

#     if ( $type == 1 )
#     {
#         $html = &Common::HTTP::get_html_page( $url );

#         foreach $line ( split "\n", $html )
#         {
#             if ( $line =~ /"Vocabulary">([^<]+)/ )
#             {
#                 push @list, $1;
#             }
#         }
#     }
#     elsif ( $type == 2 )
#     {
#         @list = &Common::HTTP::get_html_links( $url );
#         @list = grep { $_ =~ /cgi-bin/ } @list;

#         $url =~ s/\.hk.*/\.hk/;

#         @list = map { "$url$_" } @list;
#     }
#     elsif ( $type == 3 )
#     {
#         $html = &Common::HTTP::get_html_page( $url );
#         $html =~ s/<a name="\w">(\w+)<\/a>/$1/g;

#         foreach $line ( split "\n", $html )
#         {
#             if ( $line =~ /^<(p|li)>([A-Za-z]+)\s*$/ )
#             {
#                 push @list, $2;
#             }
#         }
#     }
#     elsif ( $type == 4 )
#     {
#         $html = &Common::HTTP::get_html_page( $url );

#         foreach $line ( split "\n", $html )
#         {
#             if ( $line =~ /(([a-z]+,\s*){3,3})&nbsp;/ )
#             {
#                 push @list, $1;
#             }
#         }
#     }
#     else {
#         &error( qq (Wrong looking type -> "$type") );
#     }

#     if ( not @list ) {
#         &error( qq (No list from "$url") );
#     }

#     return wantarray ? @list : \@list;
# }

# sub words_edict
# {
#     # Niels Larsen, May 2009.

#     # NOT USED

#     my ( $db,
#          $args,
#         ) = @_;

#     my ( $url, $dir, @tuples, $tuple, $page, $file, $type, @list,
#          @files, $elem, $count, $name, @links, $link, @tmp );

#     $dir = $args->{"src_dir"};
#     &Common::File::create_dir_if_not_exists( $dir );

#     $url = $db->downloads->url;

#     @tuples = ( 
#         [ "$url/frequencylists/words700.htm", "words700.tab", 1 ],
#         [ "$url/frequencylists/words2000.htm", "words2000.tab", 1 ],
#         [ "$url/frequencylists/words2-5k.htm", "words2-5k.tab", 1 ],
#         [ "$url/PhrasalVerbs", "phrasalverbs.tab", 2 ],
#         [ "$url/Verbs", "verbs.tab", 2 ],
#         [ "$url/verbs/irregular.htm", "irregverbs.tab", 4 ],
#         [ "$url/adjectives", "adjectives.tab", 2 ],
#         [ "$url/adverbs", "adverbs.tab", 2 ],
#         [ "$url/wl-1k/Basewrd1.htm", "freqwords_1000a.tab", 3 ],
#         [ "$url/wl-2k/Basewrd2.htm", "freqwords_1000b.tab", 3 ],
#         [ "$url/awl/awl.htm", "acadwords.tab", 3 ],
#         );

#     # Download,

#     foreach $tuple ( @tuples )
#     {
#         ( $page, $file, $type ) = @{ $tuple };

#         &echo( "   Fetching $file (patience) ... " );

#         if ( $type == 1 or $type == 3 or $type == 4 )
#         {
#             @list = &Words::Download::parse_edict_page( $page, $type );
#         }
#         elsif ( $type == 2 )
#         {
#             @links = &Words::Download::parse_edict_page( $page, $type );

# #            $count = &Common::Util::commify_number( scalar @links );
# #            &echo_green( "$count links\n" );

#             foreach $link ( @links )
#             {
#  #               if ( $link =~ /Table=(.+)$/ ) {
#  #                   $name = $1;
#  #               } else {
#  #                   &error( qq (Wrong looking link -> "$link") );
#  #               }

#  #               &echo( "      Getting $name ... " );
                
#                 push @list, &Words::Download::parse_edict_page( $link, 1 );

#  #               $count = &Common::Util::commify_number( scalar @list );
#  #               &echo_green( "$count total\n" );
#             }
#         }
#         else {
#             &error( qq (Wrong looking type -> "$type") );
#         }

#         foreach $elem ( @list )
#         {
#             $elem =~ s/^\s*//;
#             $elem =~ s/\s*$//;
#             $elem = lc $elem;
#         }

#         &Common::File::delete_file_if_exists( "$dir/$file" );
#         &Common::File::write_file( "$dir/$file", join "\n", @list );

#         $count = &Common::Util::commify_number( scalar @list );
#         &echo_green( "$count lines\n" );
        
#         push @files, "$dir/$file";
#     }

#     return scalar @files;
# }
