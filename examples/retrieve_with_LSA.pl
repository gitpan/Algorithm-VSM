#!/usr/bin/perl -w

### retrieve_with_LSA.pl

#use lib '../blib/lib', '../blib/arch';

use strict;
use Algorithm::VSM;

my $corpus_dir = "corpus";
#my $corpus_dir = "corpus_with_java_and_cpp";
#my $corpus_dir = "minicorpus";
#my $corpus_dir = "microcorpus";

my @query = qw/ string getAllChars throw IOException distinct TreeMap histogram map /;

my $stop_words_file = "stop_words.txt";    # This file will typically include the
                                           # keywords of the programming 
                                           # language(s) used in the software.

my ($corpus_vocab_db, $doc_vectors_db, $normalized_doc_vecs_db);

#     YOU NEED TO SET THE NEXT THREE VARIABLES ONLY FOR A PRODUCTION USE OF
#     THIS MODULE.  These three variables store the database model created
#     in three disk-based hash tables.  The three databases named below
#     store (1) the corpus vocabulary word frequency histogram; (2) the doc
#     vectors for the files in the corpus, and (3) the normalized doc
#     vectors.  Normalized document vectors are caculated by first
#     converting the word frequencies into proportions and then multiplying
#     the proportions by idf(t), which stands for "Inverse Documente
#     Frequency" at the word t.  This product is frequently displayed as
#     tf(t)xidf(t) in the IR literature.  Using the occurrence proportions
#     for tf(t) normalizes the document vector with respect to its size and
#     multiplying by idf(t) reduces the effect of the words that occur in
#     all the documents.  After these databases are created, you can do VSM
#     retrieval directly from the databases by running the script
#     retrieve_with_disk_based_VSM.pl.  Doing retrieval using a pre-stored
#     model of a corpus will, in general, be much faster since you will be
#     spared the bother of having to create the model repeatedly.
$corpus_vocab_db = "corpus_vocab_db";
$doc_vectors_db  = "doc_vectors_db";
$normalized_doc_vecs_db  = "normalized_doc_vecs_db";

my $lsa = Algorithm::VSM->new( 
                   corpus_directory         => $corpus_dir,
                   corpus_vocab_db          => $corpus_vocab_db || '',
                   doc_vectors_db           => $doc_vectors_db  || '',
                   normalized_doc_vecs_db   => $normalized_doc_vecs_db || '',
                   use_idf_filter           => 1,
                   stop_words_file          => $stop_words_file,
                   want_stemming            => 1,        # Default is no stemming
                   save_model_on_disk       => 0,        # default is 1
                   break_camelcased_and_underscored  => 1,  # default is 1
                   lsa_svd_threshold        => 0.01,# Used for rejecting singular
                                                    # values that are smaller than
                                                    # this threshold fraction of
                                                    # the largest singular value.
                   max_number_retrievals    => 10,
          );

$lsa->get_corpus_vocabulary_and_word_counts();

#    Uncomment the following statement if you would like to see the corpus
#    vocabulary:
#$lsa->display_corpus_vocab();

#    Uncomment the following statement if you would like to see the corpus
#    vocabulary size:
$lsa->display_corpus_vocab_size();

#    Uncomment the following statement if you would like to dump the corpus
#    vocabulary in a file that you supply as an argument in the following call:
$lsa->write_corpus_vocab_to_file("vocabulary_dump.txt");

#    Uncomment the following statement if you would like to see the inverse
#    document frequencies:
#$lsa->display_inverse_document_frequencies();

$lsa->generate_document_vectors();

#   Uncomment the following if you would like to see the doc vectors for
#   each of the documents in the corpus:
#$lsa->display_doc_vectors();

#    Uncomment the folloiwng statement if you would like to the individual
#    normalized document vectors:
#$lsa->display_normalized_doc_vectors();

$lsa->construct_lsa_model();

my $retrievals = $lsa->retrieve_with_lsa( \@query );

$lsa->display_retrievals( $retrievals );

