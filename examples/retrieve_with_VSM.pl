#!/usr/bin/perl -w

### retrieve_with_VSM.pl

#use lib '../blib/lib', '../blib/arch';

use strict;
use Algorithm::VSM;

my $corpus_dir = "corpus";
#my $corpus_dir = "corpus_with_java_and_cpp";
#my $corpus_dir = "minicorpus";
#my $corpus_dir = "microcorpus";

#my @query = qw/ yobj0 yobj1 /;
#my @query = qw/ scope declaration assign member local test void static /;
#my @query = qw/ program listiterator add arraylist args /;
my @query = qw/ string getallchars throw ioexception distinct treemap histogram map /;

my $stop_words_file = "stop_words.txt";    # This file will typically include the
                                           # keywords of the programming 
                                           # language(s) used in the software.

#     The two databases named below store the corpus vocabulary word
#     frequency histogram and the doc vectors for the files in the corpus,
#     respectively.  After these two databases are created, you can do VSM
#     retrieval directly from the databases by running the script
#     retrieve_with_disk_based_VSM.pl.  Doing retrieval using a pre-stored
#     model of a corpus will, in general, be much faster since you will be
#     spared the bother of having to create the model.
my $corpus_vocab_db = "corpus_vocab_db";
my $doc_vectors_db  = "doc_vectors_db";

my $vsm = Algorithm::VSM->new( 
                   corpus_directory         => $corpus_dir,
                   corpus_vocab_db          => $corpus_vocab_db,
                   doc_vectors_db           => $doc_vectors_db,
                   stop_words_file          => $stop_words_file,
                   max_number_retrievals    => 10,
                   want_stemming            => 1,      # default is no stemming
#                   debug               => 1,
          );

$vsm->get_corpus_vocabulary_and_word_counts();

$vsm->generate_document_vectors();

#    Uncomment the following statement if you would like to see the corpus
#    vocabulary:
#$vsm->display_corpus_vocab();

#    Uncomment the folloiwng statement if you would like to the individual
#    document vectors:
#$vsm->display_doc_vectors();

my $retrievals = $vsm->retrieve_with_vsm( \@query );

$vsm->display_retrievals( $retrievals );

