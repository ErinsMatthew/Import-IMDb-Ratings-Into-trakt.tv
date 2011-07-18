##############################################################
#  ImportIMDbRatingsIntoTrakt.pl - import IMDb into Trakt
#
#  ==  Syntax  ==
#  % perl ImportIMDbRatingsIntoTrakt.pl IMDbRatings.csv
#
#  ==  Overview  ==
#  This script will import your ratings from IMDb into
#  Trakt.
#
#  ==  Instructions  ==
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
#   6. Optionally change LOVE_MINIMUM to your desired value.
#      All ratings equal or higher than this value on IMDb
#      will be rated as "Love" or "Totally ninja!" on trakt.tv.
#      All others will be rated as "Hate" or "Weak sauce :(".
#   7. Login to IMDb, one of the most awesome Web sites, ever!
#   9. Save your IMDb ratings to a file using the following link.
#      <http://www.imdb.com/list/export?list_id=ratings>
#   9. Run this script, passing it the file name of your
#      IMDb ratings saved in Step 7. (See "Syntax" above.)
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

my $LOVE_MINIMUM = 6;


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

my $BATCH_SIZE = 500;

my $RECORD_SLEEP_TIME = 2_000_000;	# 2 seconds
my $BATCH_SLEEP_TIME = 30_000_000;	# 30 seconds


use constant SCRIPT_VERSION => '0.95';


#
#  globals
#
my @request_array = ();
my %request_hash;
my $request_str;
my $response;
my $decoded_response;
my %response_hash;

my $url_str;

my @ratings;
my $rating;
my $rating_idx;

my @skipped;

my $imdb_id;
my $title_str;
my $year_nbr;
my $rating_nbr;
my $rating_str;


#
#  initialize Log4perl
#
Log::Log4perl->easy_init( $DEBUG );


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
#  retrieve UNIX timestamp to use for POSTs
#
my $timestamp = time();


#
#  read CSV into string and then parse ratings
#
get_ratings_into_array( \@ratings, $csv_fn );


#
#  rate each item on Trakt
#
foreach $rating ( @ratings ) {
    $imdb_id = $rating->{ 'imdb_id' };
    $title_str = $rating->{ 'title_str' };
    $year_nbr = $rating->{ 'year_nbr' };
    $rating_nbr = $rating->{ 'rating_nbr' };


    #
    #  build rating string
    #
    if ( $rating_nbr >= $LOVE_MINIMUM ) {
        $rating_str = 'love';
    } else {
        $rating_str = 'hate';
    }


    #
    #  build JSON string to rate
    #
    %request_hash = (
        username => $TRAKT_USERNAME,
        password => $sha1_password,
        imdb_id => $imdb_id,
        title => $title_str,
        year => $year_nbr,
        rating => $rating_str
      );

    $request_str = encode_json( \%request_hash );

    $url_str = sprintf( $TRAKT_API_URL_PATTERN, 'rate', 'movie',
      $TRAKT_API_KEY );

    $response = post_to_url( $url_str, $request_str );

    DEBUG "$url_str\n\t$request_str\n\t$response\n";

    $decoded_response = decode_json( $response );

    if ( length( $decoded_response ) > 0 ) {
        %response_hash = %{ decode_json( $response ) };
    } else {
        ERROR "No response!";
    }

    $rating->{ 'rating-status' } = $response_hash{ 'status' };
    $rating->{ 'rating-error' } = $response_hash{ 'error' };


    #
    #  try to see if it's a show before giving up
    #
    if ( $rating->{ 'rating-status' } eq 'failure'
      && $rating->{ 'rating-error' } eq 'movie not found' ) {
        #
        #  sleep for a little to not overwhelm server
        #
        usleep( $RECORD_SLEEP_TIME );

        $url_str = sprintf( $TRAKT_API_URL_PATTERN, 'rate', 'show',
          $TRAKT_API_KEY );
    
        $response = post_to_url( $url_str, $request_str );
    
        DEBUG "RETRY (show): $url_str\n\t$request_str\n\t$response\n";
    
        $decoded_response = decode_json( $response );

        if ( length( $decoded_response ) > 0 ) {
            %response_hash = %{ decode_json( $response ) };
        } else {
            ERROR "No response!";
        }
    
        $rating->{ 'rating-status' } = $response_hash{ 'status' };
        $rating->{ 'rating-error' } = $response_hash{ 'error' };
    }


    #
    #  sleep for a little to not overwhelm server
    #
    usleep( $RECORD_SLEEP_TIME );
}


#
#  mark items as "Seen" on Trakt
#
$rating_idx = 1;

foreach $rating ( @ratings ) {
    #
    #  build JSON array to mark seen
    #
    push( @request_array, {
        imdb_id => $rating->{ 'imdb_id' },
        title => $rating->{ 'title_str' },
        year => $rating->{ 'year_nbr' },
        plays => 1,
        last_played => $timestamp
      } );


    if ( $rating_idx % $BATCH_SIZE == 0 ) {
        #
        #  build JSON string to mark seen
        #
        %request_hash = (
            username => $TRAKT_USERNAME,
            password => $sha1_password,
            movies => [ @request_array ]
          );
        
        $request_str = encode_json( \%request_hash );
        
        $url_str = sprintf( $TRAKT_API_URL_PATTERN, 'movie', 'seen',
          $TRAKT_API_KEY );
            
        $response = post_to_url( $url_str, $request_str );
            
        DEBUG "$url_str\n\t$request_str\n\t$response\n";

        $decoded_response = decode_json( $response );

        if ( length( $decoded_response ) > 0 ) {
            %response_hash = %{ decode_json( $response ) };
        } else {
            ERROR "No response!";
        }

        if ( $response_hash{ 'status' } eq 'success' ) {
            push( @skipped, @{ $response_hash{ 'skipped_movies' } } );
        }
    
    
        #
        #  reset values
        #
        @request_array = ();
        $rating_idx = 1;
    
    
        #
        #  sleep for a little to not overwhelm server
        #
        usleep( $BATCH_SLEEP_TIME );
    } else {
        $rating_idx++;
    }
}


#
#  process ratings not handled in previous batches
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
    
    $url_str = sprintf( $TRAKT_API_URL_PATTERN, 'movie', 'seen',
      $TRAKT_API_KEY );
        
    $response = post_to_url( $url_str, $request_str );
        
    DEBUG "$url_str\n\t$request_str\n\t$response\n";

    $decoded_response = decode_json( $response );

    if ( length( $decoded_response ) > 0 ) {
        %response_hash = %{ decode_json( $response ) };
    } else {
        ERROR "No response!";
    }

    if ( $response_hash{ 'status' } eq 'success' ) {
        push( @skipped, @{ $response_hash{ 'skipped_movies' } } );
    }
}


#
#  print summary
#
my $success_cnt = 0;
my $failure_cnt = 0;

foreach $rating ( @ratings ) {
    if ( $rating->{ 'rating-status' } eq 'failure' ) {
        $failure_cnt++;
    } else {
        $success_cnt++;
    }
}

my $total_cnt = $success_cnt + $failure_cnt;

print <<"EOT";
Ratings Processed = $total_cnt
    Success = $success_cnt
    Failure = $failure_cnt
EOT


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
#  parse ratings CSV file into array
#
sub get_ratings_into_array {
    my ( $ratings_array_ref, $file_name ) = @_;

    my $csv = Text::CSV->new( { binary => 1, eol => $/ } );

    my @ratings = read_file( $file_name );

    foreach my $rating ( @ratings ) {
        my $status = $csv->parse( $rating );
        my @fields = $csv->fields();

        my $imdb_id = $fields[ 1 ];
        my $title_str = $fields[ 6 ];
        my $year_nbr = $fields[ 9 ];
        my $rating_nbr = $fields[ 5 ];


        if ( $imdb_id =~ /tt[0-9]{7}/ ) {
            #
            #  make sure year is valid
            #
            undef $year_nbr if ( $year_nbr !~ /[0-9]{4}/ );


            #
            #  replace characters in title string
            #
            $title_str =~ s/\&#x22;//go;        # double quote


            #
            #  replace invalid characters in rating strings
            #
            $rating_nbr =~ s/\s+//go;

            undef $rating_nbr if ( $rating_nbr eq '' );


            push( @$ratings_array_ref, {
                year_nbr => $year_nbr,
                imdb_id => $imdb_id,
                title_str => $title_str,
                rating_nbr => $rating_nbr,
              } );
        }
    }
}
