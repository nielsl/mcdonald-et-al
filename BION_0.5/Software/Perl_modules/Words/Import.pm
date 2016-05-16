package Words::Import;   # -*- perl -*- 

# Description of what the routines here have 
# in common.

use strict; 
use warnings FATAL => qw ( all );

use Lingua::Stem::Snowball;

use Common::Messages;

use Registry::Args;

use Common::HTTP;
use Common::File;
use Common::Tables;

use Install::Profile;

use vars qw ( @ISA @EXPORT_OK @EXPORT );
require Exporter; @ISA = qw ( Exporter );

@EXPORT_OK = qw (
                 &create_word_list
                 &import_word_lists
                 &import_word_texts
                 &load_skip_words
                 &parse_word_wikipedia
                 &remove_wikipedia_markup
);

# >>>>>>>>>>>>>>>>>>>>>>> LOAD WORD LISTS <<<<<<<<<<<<<<<<<<<<<<<<<<<

our ( %Skip_words );

%Skip_words = &Words::Import::load_skip_words();

# >>>>>>>>>>>>>>>>>>>>> ROUTINES AND METHODS <<<<<<<<<<<<<<<<<<<<<<<<

sub create_word_list 
{
    # Niels Larsen, August 2009.

    # From a string of words, creates a list of [ word, count ]. The
    # word is lower case and longer than 2. Counts are scaled up or 
    # down against a "normal" word count of 1000.

    my ( $text,    # A string of words
        ) = @_;

    # Returns a list.

    my ( @words, %stems, @tuples, $word, $scale );

    @words = split " ", lc $text;

    @words = grep { not $Skip_words{ $_ } } @words;

    @words = grep { length $_ > 2 } @words;

#    map { $stems{ $_ }++ } &Lingua::Stem::Snowball::stem( "en", \@words );
    map { $stems{ $_ }++ } @words;

    foreach $word ( keys %stems )
    {
        push @tuples, [ $word, $stems{ $word } ];
    }

    @tuples = sort { $b->[1] <=> $a->[1] } @tuples;

    $scale = 1000.0 / (scalar @tuples);
    @tuples = map { [ $_->[0], int( $_->[1] * $scale)+1 ] } @tuples;

    return wantarray ? @tuples : \@tuples;
}

sub import_word_lists
{
    # Niels Larsen, August 2009.

    my ( $db,
         $args,
        ) = @_;

    my ( $src_dir, $ins_dir, $src_file, $ins_path, $count, $format );

    $src_dir = $args->src_dir;
    $ins_dir = $args->ins_dir;

    $format = $db->format;

    $count = 0;

    foreach $src_file ( &Common::File::list_files( $src_dir, '\.tab$' ) )
    {
        $ins_path = "$ins_dir/". $src_file->{"name"};
        $ins_path = &Common::Names::replace_suffix( $ins_path, ".$format" );

        &Common::File::create_link( $src_file->{"path"}, $ins_path );

        $count += 1;
    }

    return $count;
}

sub parse_word_wikipedia
{
    # Niels Larsen, August 2009.

    # Reads an XML wikipedia dump file, extracts keywords + frequencies, and writes
    # them to files. The text is split in persons and topics, and the file names are
    # returned. 

    my ( $db,             # Dataset object
         $conf,           # File paths
         $msgs,           # Outgoing messages
         ) = @_;

    # Returns a list.

    my ( $ifh, $line, $type, $pages, $page, $entries, $id, $title, $text, 
         %persons, %topics, %ofhs, $words, $tuples, $counts, $dir, @outputs );
    
    $ifh = &Common::File::get_read_handle( $conf->src_dir ."/xml_head.dump" );

    $line = "";
    while ( $line !~ /^\s*<page>/ ) { $line = <$ifh> };

    # Output file handles,

    $dir = $conf->tab_dir;

    @outputs = (
        [ "$dir/person_words.tab", "$dir/person_counts.tab" ],
        [ "$dir/topic_words.tab", "$dir/topic_counts.tab" ],
        );

    $ofhs{"person"}{"words"} = &Common::File::get_write_handle( $outputs[0]->[0], "clobber" => 1 );
    $ofhs{"person"}{"counts"} = &Common::File::get_write_handle( $outputs[0]->[1], "clobber" => 1 );
    $ofhs{"topic"}{"words"} = &Common::File::get_write_handle( $outputs[1]->[0], "clobber" => 1 );
    $ofhs{"topic"}{"counts"} = &Common::File::get_write_handle( $outputs[1]->[1], "clobber" => 1 );

    # Parse,

    $entries = 0;

    {
        local $/ = "</page>\n";
        
        while ( defined ( $page = <$ifh> ) )
        {
            if ( $page =~ /<title>([^<]+)<\/title>.*?<id>(\d+)<\/id>.*?<text xml:space=\"[^\"]+">(.+)<\/text>/s )
            {
                ( $title, $id, $text ) = ( $1, $2, $3 );

                $title =~ s/&[A-Za-z]+;//;
            }
            else {
                &dump( "page: $page" );
                exit;
            }

            next if $text =~ /^#REDIRECT/i;
            next if $text =~ /(can|may) refer to:/i;

            if ( $text =~ /(life|career)==/so or 
                 $text =~ /Category:\s*([^\]]+)\s* (births|deaths)/so or
                 $text =~ /(birth(_?)date|date(_?| of )birth)\s*=/so )
            {
#                $persons{ $id } = $title;
                $type = "person";
            } else {
#                $topics{ $id } = $title;
                $type = "topic";
            }
            
            # Create a string of words and years,

            $words = &Words::Import::remove_wikipedia_markup( $text );

            # Convert to a list of [ word, count ],

            $tuples = &Words::Import::create_word_list( $words );

            $words = join ",", map { $_->[0] } @{ $tuples };
            $counts = join ",", map { $_->[1] } @{ $tuples };

            $ofhs{ $type }{"words"}->print( "$id\t$words\n" );
            $ofhs{ $type }{"counts"}->print( "$id\t$counts\n" );

            $entries += 1;
        }
    }
    
    $ifh->close;

    $ofhs{"person"}{"words"}->close;
    $ofhs{"person"}{"counts"}->close;
    $ofhs{"topic"}{"words"}->close;
    $ofhs{"topic"}{"counts"}->close;

#    &dump( $entries );
#    &dump( \%persons );
#    &dump( \%topics );

    return ( \@outputs, $entries );
}

sub import_word_texts
{
    my ( $db,
         $conf,
         $msgs,
        ) = @_;

    my ( $routine, $outputs, $entries );

    $routine = "Words::Import::parse_". $db->name;

#    Registry::Check->routine_exists( 

    {
        no strict "refs";
        
        eval { ( $outputs, $entries ) = $routine->( $db, $conf, $msgs ) };
        
    };
        
    &dump( $outputs );
    &dump( $entries );

    exit;

    return;
}

sub load_skip_words
{
    # Niels Larsen, August 2009.

    # Loads lists of words to skip. Words are key, and all lower 
    # case.

    # Returns a hash.

    my ( $db, $conf, $dir, $words, $fmt );

    $db = Registry::Get->dataset("word_edict");
    $conf = &Install::Profile::create_install_config( $db );

    $dir = $conf->ins_dir;
    $fmt = $db->format;

    %Skip_words = ();

    $words = ${ &Common::File::read_file( "$dir/stopwords.$fmt" ) };
    map { $Skip_words{ $_ } = 1 } split /\s+/, $words;

    $words = ${ &Common::File::read_file( "$dir/conjunctions.$fmt" ) };
    map { $Skip_words{ $_ } = 1 } split /\s+/, $words;

    $words = ${ &Common::File::read_file( "$dir/prepositions.$fmt" ) };
    map { $Skip_words{ $_ } = 1 } split /\s+/, $words;

    $words = ${ &Common::File::read_file( "$dir/pronouns.$fmt" ) };
    map { $Skip_words{ $_ } = 1 } split /\s+/, $words;

    # html tags: if tag removal systematically fails, then these will be 
    # in all pages and make noise. Here we remove a subset of tags that 
    # are likely not real text, as a last resort,

    $words = [ qw ( abbr applet basefont bdo big blockquote br button caption
center cite code col colgroup dd del dfn dir div dl dt em fieldset form frame
frameset hr iframe img input ins kbd label li link menu meta noframes noscript
ol optgroup param pre samp select small span strong style sub sup tbody textarea
tfoot thead var ) ];

    map { $Skip_words{ $_ } = 1 } @{ $words };

    return wantarray ? %Skip_words : \%Skip_words;
}

sub remove_wikipedia_markup
{
    # Niels Larsen, August 2009.

    # Removes unwanted parts of a Wikipedia page so that left are just plain words;
    # see code for detail. First major chunks like tables and citations are removed, 
    # then smaller stuff. Or expressions are slow and are avoided. Markup description,
    # http://en.wikipedia.org/wiki/Wikipedia:HOW

    my ( $text,
         ) = @_;

    my ( $tags, $links );

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHUNKS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text =~ s/\{\|.+?\|\}//gs;                        # Entire tables with content
    
    $text =~ s/&gt;/>/igs;                  # De-webbify > and < 
    $text =~ s/&lt;/</igs;                  # so deletions below work

    $text =~ s/<ref(.+?)<\/ref>//igs;                      # References
    $text =~ s/<ref(.+?)<?\/(ref)?>//igs;                  #      -
    $text =~ s/<!--(.+?)-->//gs;                           # Comments
    $text =~ s/<source(.+?)<\/source>//igs;                # Source code
    $text =~ s/<math(.+?)<\/math>//igs;                    # Math
    $text =~ s/<div(.+?)<\/div>//igs;                      # <div> tags
    $text =~ s/<span(.+?)<\/span>//igs;                    # <span> tags
    $text =~ s/<gallery(.+?)<\/gallery>//igs;              # <gallery> chunks

    $text =~ s/{{refbegin}}.+?{{refend}}//gs;      # Delete references and citations
    $text =~ s/{{[^{}]+}}//gs;                     # Delete brace regions
    $text =~ s/{{[^{}]+}}//gs;                     #  - which can be nested
    $text =~ s/{{[^{}]+}}//gs;                     #  - and once more

    $text =~ s/\[\[Image:[^\n]+//igs;              # Images to end of line
    $text =~ s/\[\[[\w-]+:[^\]]+\]\]\s*//gs;       # Remove categories, translation, etc.

    $text =~ s/={2,}\s?[^=]+={2,}//gs;             # Delete titles
    $text =~ s/\[http:\/\/(.+?)\]//igs;            # Delete links
    $text =~ s/\http:\/\/([^ ]+)//igs;             # Delete links, bad style

    $text =~ s/ISBN\s*[\w-]+//igs;                 # ISBN numbers

    # >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CHARACTERS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    $text =~ s/&[a-z]+;([a-z]+;)?//igs;       # Web characters, &quot; etc

    $text =~ s/[^A-Za-z0-9\n]/ /gs;           # Delete non-word characters except \n
    $text =~ s/\b\d{1,3}\b/ /gs;              # Delete numbers up to 3 digits
    $text =~ s/\b\d{5,}\b/ /gs;               # Delete numbers over 4 digits
    $text =~ s/\b\w\b/ /gs;                   # Delete single characters

    $text =~ s/\s+/ /gs;                  # Remove multiple spaces/newlines

    return $text;

    # >>>>>>>>>>>>>>>>>>>>>>>>> RETIRED EXPRESSIONS <<<<<<<<<<<<<<<<<<<<<<<<

    # Some markup spans text that should be removed,

#    $text =~ s/\{\{cite.+?\}\}//gs;                    # Citations of all kinds
#    $text =~ s/\{\{\S+?\}\}//gs;
#    $text =~ s/\{\{[\w\-\s]+[:\|](.+?)\}\}/$1/gs;

    $text =~ s/\{\{pad\|(.*?)\}\}//igs;                    # Padding
    $text =~ s/\{\{[A-Za-z]+\|(.+?)\}\}/$1/gs;
    $text =~ s/\{\{(.+?)\}\}//g;

    $links = join "|", qw ( Image media InterWiki Wiktionary Wikipedia Category );

    $text =~ s/\[\[:?($links)(.+?)\]\]//igs; 

    $text =~ s/(\[\[|\]\])//g;

    # Some tags can be stripped without removing the text between,

    $tags = join "|", qw ( nowiki small big u s del ins pre table tr th td sup center gallery );

    $text =~ s/<\/?($tags)>//ig;
    $text =~ s/<br\s+>//ig;
    $text =~ s/\S+\s*=//gs;

    $text =~ s/\{\{[A-Z]+\}\}//g;
    $text =~ s/\{\{ns:\d+\}\}//g;
    $text =~ s/\{\{(local|full)url(.*?)\}\}//g;

    $text =~ s/[\*=~'"\\]//sg;
    $text =~ s/[\|():\.,;]/ /sg;

    return $text;
}
    
1;

__END__
