#!/usr/bin/perl -w

### calculate_precision_and_recall_for_LSA.pl

#use lib '../blib/lib', '../blib/arch';

##    This is a self-contained script for precision-and-recall calculatins with
##    LSA.  Therefore, it is NOT necessary that your first create the disk-based
##    hash tables by calling retrieve_with_LSA.pl

use strict;
use Algorithm::VSM;

my $corpus_dir = "corpus";                     # This is the directory containing
                                               # the corpus
#my $corpus_dir = "corpus_with_java_and_cpp";
#my $corpus_dir = "minicorpus";
#my $corpus_dir = "microcorpus";

my $corpus_vocab_db = "corpus_vocab_db";       # The corpus-wide histogram of the
                                               # vocabulary is stored in this 
                                               # DBM file.

my $doc_vectors_db  = "doc_vectors_db";        # Using the Storable module, we
                                               # store all the doc vectors in 
                                               # this diskfile.

my $normalized_doc_vecs_db = "normalized_doc_vecs_db";
                                               # Using the Storable module, we
                                               # store the normalized vectors
                                               # for the document in this database.
                                               # Normalization means replacing the
                                               # term occurrence counts by relative 
                                               # frequencies and multiplying by
                                               # idf(t) 

my $stop_words_file = "stop_words.txt";        # Will typically include the 
                                               # keywords of the programming
                                               # language(s) used in the software.

my $query_file      = "test_queries.txt";      # This file contains the queries
                                               # to be used for precision vs.
                                               # recall analysis.  Its format
                                               # must be as shown in test_queries.txt

my $relevancy_file   = "relevancy.txt";        # The generated relevancies will
                                               # be stored in this file.

my $lsa = Algorithm::VSM->new( 
                   corpus_directory    => $corpus_dir,
                   corpus_vocab_db     => $corpus_vocab_db,
                   doc_vectors_db      => $doc_vectors_db,
                   normalized_doc_vecs_db   => $normalized_doc_vecs_db,
                   stop_words_file     => $stop_words_file,
                   query_file          => $query_file,
                   want_stemming       => 1,
                   break_camelcased_and_underscored  => 1,
                   lsa_svd_threshold   => 0.05,     # Used for rejecting singular
                                                    # values that are smaller than
                                                    # this threshold fraction of
                                                    # the largest singular value.
                   relevancy_threshold => 5,    # Used when estimating relevancies
                                                # with the method 
                                                # estimate_doc_relevancies().  A
                                                # doc must have at least this 
                                                # number of query words to be
                                                # considered relevant.
                   relevancy_file      => $relevancy_file,   # Relevancy judgments
                                                             # are deposited in 
                                                             # this file.
#                   debug              => 1,
          );

$lsa->get_corpus_vocabulary_and_word_counts();

$lsa->generate_document_vectors();

#    Uncomment the following statement if you want to see the corpus
#    vocabulary:
#$lsa->display_corpus_vocab();

#    Uncomment the following statement if you want to see the individual
#    document vectors:
#$lsa->display_doc_vectors();

$lsa->construct_lsa_model();

#    The argument below is the file that contains the queries to be used
#    for precision-recall analysis.  The format of this file must be
#    according to what is shown in the file test_queries.txt in this
#    directory:
$lsa->estimate_doc_relevancies();

#    Uncomment the following statement if you wish to see the list of all
#    the documents relevant to each of the queries:
#$lsa->display_doc_relevancies();

$lsa->precision_and_recall_calculator('lsa');

$lsa->display_precision_vs_recall_for_queries();

$lsa->display_map_values_for_queries();

