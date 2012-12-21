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

#     The three databases named below store (1) the corpus vocabulary word
#     frequency histogram; (2) the doc vectors for the files in the corpus,
#     and (3) the normalized doc vectors.  Normalized document vectors are
#     caculated by first converting the word frequencies into proportions
#     and then multiplying the proportions by idf(t), which stands for
#     "Inverse Documente Frequency" at the word t.  This product is 
#     frequently displayed as tf(t)xidf(t) in the IR literature.  Using the
#     occurrence proportions for tf(t) normalizes the document vector with
#     respect to its size and multiplying by idf(t) reduces the effect of 
#     the words that occur in all the documents.

#     After these databases are created, you can do VSM retrieval directly 
#     from the databases by running the script retrieve_with_disk_based_VSM.pl.  
#     Doing retrieval using a pre-stored model of a corpus will, in general, 
#     be much faster since you will be spared the bother of having to create 
#     the model repeatedly.
my $corpus_vocab_db = "corpus_vocab_db";
my $doc_vectors_db  = "doc_vectors_db";
my $normalized_doc_vecs_db  = "normalized_doc_vecs_db";

my $vsm = Algorithm::VSM->new( 
                   corpus_directory         => $corpus_dir,
                   corpus_vocab_db          => $corpus_vocab_db,
                   doc_vectors_db           => $doc_vectors_db,
                   normalized_doc_vecs_db   => $normalized_doc_vecs_db,
#                   use_idf_filter          => 0,
                   stop_words_file          => $stop_words_file,
                   max_number_retrievals    => 10,
                   want_stemming            => 1,      # default is no stemming
#                   debug                    => 1,
          );

$vsm->get_corpus_vocabulary_and_word_counts();

#    Uncomment the following statement if you would like to see the corpus
#    vocabulary:
#$vsm->display_corpus_vocab();


#    Uncomment the following statement if you would like to see the inverse
#    document frequencies:
#$vsm->display_inverse_document_frequencies();

$vsm->generate_document_vectors();

#    Uncomment the folloiwng statement if you would like to the individual
#    document vectors:
#$vsm->display_doc_vectors();


#    Uncomment the folloiwng statement if you would like to the individual
#    normalized document vectors:
#$vsm->display_normalized_doc_vectors();

my $retrievals = $vsm->retrieve_with_vsm( \@query );

$vsm->display_retrievals( $retrievals );

