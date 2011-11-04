#!/usr/bin/perl -w

### retrieve_with_disk_based_LSA.pl

#use lib '../blib/lib', '../blib/arch';

use strict;
use Algorithm::VSM;

print "\nIMPORTANT:  We assume that you have previously called\n\n" .
      "                   retrieve_with_VSM.pl              \n\n" .
      "on the same corpus and that the database files generated by\n" .
      "that call were not overwritten by intervening calls to either\n" .
      "the retrieve_with_LSA() script or the retrieve_with_VSM.pl script.\n\n";

#my @query = qw/ yobj0 yobj1 /;
#my @query = qw/ scope declaration assign member local test void static /;
#my @query = qw/ program listiterator add arraylist args /;
my @query = qw/ string getallchars throw ioexception distinct treemap histogram map /;

#     The three databases mentioned in the next three statements are
#     created by calling the retrieve_with_VSM.pl script.  The first of the
#     databases stores the corpus vocabulary and term frequencies for the
#     vocabulary words.  The second database stores the term frequency
#     vectors for the individual documents in the corpus. The third database
#     stores the normalized document vectors.  As to what is meant by document
#     normalization, see the script retrieve_with_VSM.pl
my $corpus_vocab_db = "corpus_vocab_db";
my $doc_vectors_db  = "doc_vectors_db";
my $normalized_doc_vecs_db = "normalized_doc_vecs_db";

my $lsa = Algorithm::VSM->new( 
                   corpus_vocab_db          => $corpus_vocab_db,
                   doc_vectors_db           => $doc_vectors_db,
                   normalized_doc_vecs_db   => $normalized_doc_vecs_db,
                   max_number_retrievals    => 10,
#                  debug                    => 1,
          );

$lsa->upload_normalized_vsm_model_from_disk();

#   Uncomment the following if you would like to see the corpus vocabulary:
#$lsa->display_corpus_vocab();

#   Uncomment the following if you would like to see the doc vectors for
#   each of the documents in the corpus:
#$lsa->display_doc_vectors();


$lsa->construct_lsa_model();

my $retrievals = $lsa->retrieve_with_lsa( \@query );

$lsa->display_retrievals( $retrievals );

