#!/bin/perl
use strict;
use warnings;

use CGI;
use WWW::Curl::Easy;
use Apache2::Response;

use constant  DEFAULT_SCHEME => 'https://';

sub  do_usage($)
{
    my $q = shift;
    print $q->header(
        -type => "text/plain",
        -status => "200 OK",
     );
    
    my $host = $ENV{HTTP_HOST};
    
    print <<EOD
$ENV{REQUEST_URI} invalido.
Uso: https://${host}/https://google.com
EOD
;
    return 0;
}

our  @chuncks = ();
our  $status = undef;

sub write_callback()
{
    my $var;
    my $len = 0;
    while( $var = shift )
    {
        $len += length($var);
        
        chomp $var;
        $var =~ s/\r$//;
        
        if( !$status && $var =~ /^HTTP\// )
        {
            $status = $var;
            $status =~ s/^[^\s]*\s//;
        }
        else
        {        
            push @chuncks, $var;
        }
    }
    return  $len;
}

sub  build_headers
{
    my @h = ();
    push @h, "Content-Type: " . $ENV{CONTENT_TYPE} if $ENV{CONTENT_TYPE};
    push @h, "Content-Lenght: " . $ENV{CONTENT_LENGTH} if $ENV{CONTENT_LENGTH};
    
    for my $hh ( keys %ENV )
    {
        my $key = $hh;
        next unless $hh =~ /^HTTP_/;
        next if $hh eq "HTTP_HOST";
        $hh =~ s/^HTTP_//;
        $hh =~ s/_/-/;
        push @h, lc( $hh ) . ": " . $ENV{$key};
    } 
    return \@h;
}

sub  do_debug_request()
{
    if( $ENV{HTTP_MYPROXY_DEBUG} )
    {
        print "\n----- $status-\n";
        for ( @chuncks )
        {
            print " RESP> " . $_ . "\n";
        }
        
        for ( @{&build_headers} )
        {
            print " HEAD> " . $_ . "\n";
        }
        
        for ( keys %ENV )
        {
            print " ENV> $_ = $ENV{$_}\n";
        }
        
        
        print  "----- FIN";
        return 1;
    }
    return 0
}

sub  get_scheme
{
    return $ENV{REQUEST_SCHEME} . "://" if $ENV{REQUEST_SCHEME};
    return $ENV{HTTP_X_FORWARDED_PROTO} . "://" if $ENV{HTTP_X_FORWARDED_PROTO};
    return DEFAULT_SCHEME;
}

sub  do_proxy( $$ )
{
    my ($q,$uri) = @_;
    
    my $curl = WWW::Curl::Easy->new;
    my $retcode;
    my $response_body;
    
    $curl->setopt(CURLOPT_URL, $uri );
    $curl->setopt(CURLOPT_HEADER, 0 );
    $curl->setopt(CURLOPT_HEADERFUNCTION, \&write_callback);
    $curl->setopt(CURLOPT_HTTPHEADER, &build_headers );
    $curl->setopt(CURLOPT_WRITEDATA,\$response_body);
    
    $retcode = $curl->perform();
    
    if( $retcode == 0 )
    {
    
        my $response_code = $curl->getinfo(CURLINFO_RESPONSE_CODE);
        my $content_type = $curl->getinfo(CURLINFO_CONTENT_TYPE);
        
        my %headers = (
            -status => $status,
            # -type => $content_type,
            "-x-myproxy-request-uri" => $uri,
            "-x-myproxy-response" => $response_code,
          );
        
        
       
        for( @chuncks )
        {
            next unless $_;
            my ( $key, $val ) = split /: /, $_, 2;
            next if $response_code != 200 && lc( $key ) eq "content-length";
            next if lc( $key ) eq "transfer-encoding";
            $val = get_scheme . $ENV{HTTP_HOST} . "/" . $val if lc( $key ) eq "location";
            $headers{"-".$key} = $val;
        }
        
        print  $q->header( %headers );
        
        print $response_body if( do_debug_request() || $response_code == 200 );
        
    }
    else
    {
        print $q->header(
            -status => "503 Service Unavailable",
            -type => 'text/plain',
            "-x-myproxy-request-uri" => $uri,
            "-x-myproxy-error" => "Error $retcode: " . $curl->strerror($retcode),
            "-x-myproxy-errorbuf" => $curl->errbuf,
         );
         return do_debug_request();
    }
}

my $q = CGI->new;



my $uri = $q->param( 'uri' );
$uri = $q->url_param( 'uri' ) if( !$uri );
$uri = $ENV{REQUEST_URI} if( !$uri );

if( $uri && $uri =~ /^\/?https?:\/\// ){
    $uri =~ s/^\///;
    do_proxy( $q, $uri )
}
else
{
    do_usage $q;
    print "URI: $uri\n";
}

1;
