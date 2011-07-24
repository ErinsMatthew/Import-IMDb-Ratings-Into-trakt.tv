##############################################################
#  ImportIMDbWatchlistIntoTrakt.pl - import watchlist into Trakt
#
#  ==  Syntax  ==
#  % perl ImportIMDbWatchlistIntoTrakt.pl IMDbWatchlist.csv
#
#  ==  Overview  ==
#  This script will import your watchlist from IMDb into
#  Trakt.
#
#  ==  Instructions  ==
#  This script should be able to run on all platforms
#  that support Perl and the dependencies below.
#
#  To use this script, you will need to perform the
#  following steps.
#
#   1. Make sure you have Perl installed. I recommend
#      ActiveState's ActivePerl.
#   2. Make sure you have the following dependencies
#      before starting. Some come with ActivePerl.
#      For those that don't you can download them from
#      CPAN.org or use the "cpan" command-line program
#      once you install ActiveState's ActivePerl.
#
#      Digest::SHA1
#      LWP
#      Time::HiRes
#      File::Slurp
#      Log::Log4perl
#      Text::CSV
#      URI::Escape
#      JSON
#
#   3. Login to trakt.tv. <http://trakt.tv/>
#   4. Get your API key (everyone has one). <http://trakt.tv/settings/api>
#   5. Enter your trakt.tv username, password,
#      and API key below where it says "<Enter Value Here>". Save!
#   6. Login to IMDb, one of the most awesome Web sites, ever!
#   7. Save your IMDb Watchlist to a file using the following link.
#      <http://www.imdb.com/list/export?list_id=watchlist>
#   9. Run this script, passing it the file name of your
#      IMDb watchlist saved in Step 7. (See "Syntax" above.)
#  10. Voilà!
#  11. Submit error reports, or, better yet, submit code
#      patches to the project's GitHub site.
#      <https://github.com/ErinsMatthew/Import-IMDb-Ratings-Into-trakt.tv>
#
#  ==  License  ==
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program. If not, see <http://www.gnu.org/licenses/>.
##############################################################


my $TRAKT_USERNAME = '<Enter Value Here>';
my $TRAKT_PASSWORD = '<Enter Value Here>';
my $TRAKT_API_KEY = '<Enter Value Here>';


#####             ===  WARNING * WARNING * WARNING  ===           #####
#####                                                             #####
#####  DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU'RE DOING!  #####
#####                                                             #####
#####             ===  WARNING * WARNING * WARNING  ===           #####


use strict;


use Digest::SHA1 qw( sha1_hex );
use LWP;
use Time::HiRes qw( usleep );
use File::Slurp;
use Log::Log4perl qw( :easy );
use Text::CSV;
use URI::Escape;
use JSON;


#
#  keep JSON from displaying debug information
#
undef $JSON::DEBUG;


#
#  constants
#
my $DEFAULT_VALUE =  '<Enter Value Here>';

my $TRAKT_API_URL_PATTERN = 'http://api.trakt.tv/%s/%s/%s';
my $TRAKT_USER_LIBRARY_URL_PATTERN = 'http://api.trakt.tv/user/watchlist/%s.json/%s/%s';

my $IGNORE_FILE_NAME = 'IMDbIdsToIgnore.txt';

my $BATCH_SIZE = 50;

my $RECORD_SLEEP_TIME = 3_000_000;	# 2 seconds
my $BATCH_SLEEP_TIME = 30_000_000;	# 30 seconds


use constant SCRIPT_VERSION => '0.5';


#
#  globals
#
my @request_array = ();
my %request_hash;
my $request_str;
my $response;
my $decoded_response;
my %response_hash;
my @response_array;

my $url_str;

my @movies;
my $movie;
my $movie_idx;

my %in_watchlist;

my %imdb_ids_to_ignore;

my $imdb_id;
my $title_str;
my $year_nbr;


#
#  initialize Log4perl
#
Log::Log4perl->easy_init( {
#    level => $ERROR,
    level => $DEBUG,
    file => '>ImportIMDbWatchlistIntoTrakt.log'
  } );


#
#  check values
#
if ( $TRAKT_API_KEY eq $DEFAULT_VALUE ) {
    ERROR "You must set your Trakt API key before proceeding.\n";

    exit -1;
}

if ( $TRAKT_USERNAME eq $DEFAULT_VALUE ) {
    ERROR "You must set your Trakt username before proceeding.\n";

    exit -1;
}

if ( $TRAKT_PASSWORD eq $DEFAULT_VALUE ) {
    ERROR "You must set your Trakt password before proceeding.\n";

    exit -1;
}


#
#  read CSV filename from command-line
#
my $csv_fn = $ARGV[ 0 ];


#
#  convert password to SHA1 digest
#
my $sha1_password = sha1_hex( $TRAKT_PASSWORD );


#
#  read ignore file into hash
#
read_ignore_file_into_hash( \%imdb_ids_to_ignore );


#
#  retrieve user's current watchlist on Trakt
#
$url_str = sprintf( $TRAKT_USER_LIBRARY_URL_PATTERN, 'movies',
  $TRAKT_API_KEY, $TRAKT_USERNAME );

$response = get_html( $url_str );

DEBUG "$url_str\n\t$response\n";

$decoded_response = decode_json( $response );

if ( length( $decoded_response ) > 0 ) {
    @response_array = @{ decode_json( $response ) };
} else {
    ERROR "No response!";
}

foreach $movie ( @response_array ) {
    $imdb_id = $movie->{ 'imdb_id' };
    $title_str = $movie->{ 'title' };

    if ( $imdb_id ne '' ) {
        $in_watchlist{ $imdb_id }++;
    } else {
        WARN "$title_str does not have an IMDb number."
    }
}

DEBUG 'There are ' . scalar( keys( %in_watchlist ) ) . ' items in the watchlist already.';


#
#  read CSV into string and then parse movies
#
get_watchlist_into_array( \@movies, $csv_fn );

DEBUG 'There are ' . scalar( @movies ) . ' items in the IMDb watchlist.';


#
#  add items to watchlist on trakt
#
$movie_idx = 1;

ITEM: foreach $movie ( @movies ) {
    #
    #  skip movie if it's already in the user's trakt watchlist
    #
    $imdb_id = $movie->{ 'imdb_id' };

    if ( $imdb_id eq '' || $in_watchlist{ $imdb_id } ) {
        next ITEM;
    }


    #
    #  skip movie if it's being ignored
    #
    $title_str = $movie->{ 'title_str' };

    if ( $imdb_ids_to_ignore{ $imdb_id } ) {
        DEBUG "Ignoring '$title_str'.";

        next ITEM;
    }


    #
    #  build JSON array to mark seen
    #
    push( @request_array, {
        imdb_id => $imdb_id,
        title => $title_str,
        year => $movie->{ 'year_nbr' }
      } );


    if ( $movie_idx % $BATCH_SIZE == 0 ) {
        #
        #  build JSON string to mark seen
        #
        %request_hash = (
            username => $TRAKT_USERNAME,
            password => $sha1_password,
            movies => [ @request_array ]
          );
        
        $request_str = encode_json( \%request_hash );
        
        $url_str = sprintf( $TRAKT_API_URL_PATTERN, 'movie', 'watchlist',
          $TRAKT_API_KEY );
            
        $response = post_to_url( $url_str, $request_str );
            
        DEBUG "$url_str\n\t$request_str\n\t$response\n";

        $decoded_response = decode_json( $response );

        if ( length( $decoded_response ) > 0 ) {
            %response_hash = %{ decode_json( $response ) };
        } else {
            ERROR "No response!";
        }

    
        #
        #  reset values
        #
        @request_array = ();
        $movie_idx = 1;
    
    
        #
        #  sleep for a little to not overwhelm server
        #
        usleep( $BATCH_SLEEP_TIME );
    } else {
        $movie_idx++;
    }
}


#
#  process movies not handled in previous batches
#
if ( scalar( @request_array ) > 1 ) {
    #
    #  build JSON string to mark seen
    #
    %request_hash = (
        username => $TRAKT_USERNAME,
        password => $sha1_password,
        movies => [ @request_array ]
      );
    
    $request_str = encode_json( \%request_hash );
    
    $url_str = sprintf( $TRAKT_API_URL_PATTERN, 'movie', 'watchlist',
      $TRAKT_API_KEY );
        
    $response = post_to_url( $url_str, $request_str );
        
    DEBUG "$url_str\n\t$request_str\n\t$response\n";

    $decoded_response = decode_json( $response );

    if ( length( $decoded_response ) > 0 ) {
        %response_hash = %{ decode_json( $response ) };
    } else {
        ERROR "No response!";
    }
}


#####


#
#  post data to a specified URL
#
sub post_to_url {
    my ( $URL, $data ) = @_;


    my $UserAgent = LWP::UserAgent->new();

    my $Request = HTTP::Request->new( POST => $URL );

    $Request->content_type( 'application/x-www-form-urlencoded' );
    $Request->content( $data );


    my $Response = $UserAgent->request( $Request );

    return $Response->content;
}


#
#  get data from a specified URL
#
sub get_html {
    my ( $URL ) = @_;


    my $UserAgent = LWP::UserAgent->new();

    my $Request = HTTP::Request->new( GET => $URL );
    my $Response = $UserAgent->request( $Request );

    return $Response->content;
}


#
#  parse movies CSV file into array
#
sub get_watchlist_into_array {
    my ( $movies_array_ref, $file_name ) = @_;

    my $csv = Text::CSV->new( { binary => 1, eol => $/ } );

    my @movies = read_file( $file_name );

    foreach my $movie ( @movies ) {
        my $status = $csv->parse( $movie );
        my @fields = $csv->fields();

        my $imdb_id = $fields[ 1 ];
        my $title_str = $fields[ 6 ];
        my $year_nbr = $fields[ 9 ];


        if ( $imdb_id =~ /tt[0-9]{7}/ ) {
            #
            #  make sure year is valid
            #
            undef $year_nbr if ( $year_nbr !~ /[0-9]{4}/ );


            #
            #  replace characters in title string
            #
            $title_str =~ s/\&#x22;//go;        # double quote


            push( @$movies_array_ref, {
                year_nbr => $year_nbr,
                imdb_id => $imdb_id,
                title_str => $title_str
              } );
        }
    }
}


sub read_ignore_file_into_hash {
    my ( $hash_ref ) = @_;


    if ( -f "$IGNORE_FILE_NAME" ) {
        open( IDS, "<$IGNORE_FILE_NAME" );
    
        while ( <IDS> ) {
            chomp;
    
            $$hash_ref{ $_ }++;
        }
    
        close( IDS );
    }
}
