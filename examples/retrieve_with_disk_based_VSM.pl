#!/usr/bin/perl -w

### retrieve_with_disk_based_VSM.pl

#use lib '../blib/lib', '../blib/arch';

use strict;
use Algorithm::VSM;


print "\nIMPORTANT:  We assume that you have previously called\n\n" .
      "                   retrieve_with_VSM.pl              \n\n" .
      "on the same corpus and that the database files generated by\n" .
      "that call were not overwritten by intervening calls to either\n" .
      "the retrieve_with_LDA() script or the retrieve_with_VSM.pl script.\n\n";

#my @query = qw/ yobj0 yobj1 /;
#my @query = qw/ scope declaration assign member local test void static /;
#my @query = qw/ program listiterator add arraylist args /;
my @query = qw/ string getallchars throw ioexception distinct treemap histogram map /;

#     The two databases mentioned in the next two statements are created by
#     calling the retrieve_with_VSM.pl script.  The first of the databases
#     stores the corpus vocabulary and the term frequencies for the
#     vocabulary words.  The second database stores the doc vectors of the
#     VSM model.
my $corpus_vocab_db = "corpus_vocab_db";
my $doc_vectors_db  = "doc_vectors_db";

my $vsm = Algorithm::VSM->new( 
                   corpus_vocab_db           => $corpus_vocab_db, 
                   doc_vectors_db            => $doc_vectors_db,
                   max_number_retrievals     => 10,
#                  debug                     => 1,
          );

$vsm->upload_vsm_model_from_disk();

#    Uncomment the following statement if you would like to see the corpus
#    vocabulary:
#$vsm->display_corpus_vocab();

#    Uncomment the folloiwng statement if you would like to the individual
#    document vectors:
#$vsm->display_doc_vectors();

my $retrievals = $vsm->retrieve_with_vsm( \@query );

$vsm->display_retrievals( $retrievals );

