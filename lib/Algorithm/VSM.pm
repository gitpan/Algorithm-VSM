package Algorithm::VSM;

#---------------------------------------------------------------------------
# Copyright (c) 2011 Avinash Kak. All rights reserved.  This
# program is free software.  You may modify and/or
# distribute it under the same terms as Perl itself.  This
# copyright notice must remain attached to the file.
#
# Algorithm::VSM is a pure-Perl implementation for
# retrieving documents from software libraries that match a
# list of words in a query.  Document are matched with
# queries using a similarity criterion that depends on
# whether your model for the entire library is based on the
# full-dimensionality VSM or on the reduced-dimensionality
# LSA.
# ---------------------------------------------------------------------------

use 5.10.0;
use strict;
use warnings;
use Carp;
use SDBM_File;
use Fcntl;
use Storable;
use Cwd;

our $VERSION = '1.0';

#############################   Constructor  ########################

#  Constructor for constructing VSM or LSA model of a corpus.  The object
#  returned by the constructor can be used for retrieving documents from
#  the corpus in response to queries.
sub new { 
    my ($class, %args) = @_;
    my @params = keys %args;
    croak "\nYou have used a wrong name for a keyword argument " .
          "--- perhaps a misspelling\n" 
          if _check_for_illegal_params(@params) == 0;
    bless {
        _corpus_directory      =>  $args{corpus_directory} 
                                        || "",
        _corpus_vocab_db       =>  $args{corpus_vocab_db} || "corpus_vocab_db",
        _doc_vectors_db        =>  $args{doc_vectors_db} || "doc_vectors_db",
        _lsa_doc_vectors_db    =>  $args{lsa_doc_vectors_db} 
                                        || "lsa_doc_vectors_db",
        _stop_words_file       =>  $args{stop_words_file} || "",
        _query_file            =>  $args{query_file} || "",
        _min_word_length       =>  $args{min_word_length} || 4,
        _want_stemming         =>  $args{want_stemming} || 0,
        _max_number_retrievals =>  $args{max_number_retrievals} || 30,
        _lsa_svd_threshold     =>  $args{lsa_svd_threshold} || 0.01,
        _relevancy_threshold   =>  $args{relevancy_threshold} || 1,
        _relevancy_file        =>  $args{relevancy_file} || "",
        _debug                 =>  $args{debug} || 0,
        _working_directory     =>  cwd,
        _vocab_hist_on_disk    =>  {},
        _vocab_hist            =>  {},
        _doc_hist_template     =>  {},
        _corpus_doc_vectors    =>  {},
        _query_vector          =>  {},
        _stop_words            =>  [],
        _term_document_matrix  =>  [],
        _corpus_vocab_done     =>  0,
        _scan_dir_for_rels     =>  0,
        _vocab_size            =>  undef,
        _doc_vecs_trunc_lsa    =>  {},
        _lsa_vec_truncator     =>  undef,
        _queries_for_relevancy =>  {},
        _relevancy_estimates   =>  {},
        _precision_for_queries =>  {},
        _recall_for_queries    =>  {},
        _map_vals_for_queries  =>  {},
    }, $class;
}


################    Get corpus vocabulary and word counts  ##################

sub get_corpus_vocabulary_and_word_counts {
    my $self = shift;
    die "You must supply the name of the corpus directory to the constructor"
        unless $self->{_corpus_directory};
    print "Scanning the directory '$self->{_corpus_directory}' for\n" .
        "  model construction\n\n" if $self->{_debug};
    unlink glob $self->{_corpus_vocab_db};
    tie %{$self->{_vocab_hist_on_disk}}, 'SDBM_File',  
             $self->{_corpus_vocab_db}, O_RDWR|O_CREAT, 0640
            or die "Can't create DBM files: $!";       
    $self->_scan_directory( $self->{_corpus_directory} );
    $self->_drop_stop_words() if $self->{_stop_words_file};
    if ($self->{_debug}) {
        foreach ( sort keys %{$self->{_vocab_hist_on_disk}} ) {               
            printf( "%s\t%d\n", $_, $self->{_vocab_hist_on_disk}->{$_} );    
        }
    }
    foreach (keys %{$self->{_vocab_hist_on_disk}}) {
        $self->{_vocab_hist}->{$_} = $self->{_vocab_hist_on_disk}->{$_};
    }
    untie %{$self->{_vocab_hist_on_disk}};
    $self->{_corpus_vocab_done} = 1;
    $self->{_vocab_size} = scalar( keys %{$self->{_vocab_hist}} );
    print "\n\nVocabulary size:  $self->{_vocab_size}\n\n"
            if $self->{_debug};
}

sub generate_document_vectors {
    my $self = shift;
    chdir $self->{_working_directory};
    foreach ( sort keys %{$self->{_vocab_hist}} ) {
        $self->{_doc_hist_template}->{$_} = 0;    
    }
    $self->_scan_directory( $self->{_corpus_directory} );
    chdir $self->{_working_directory};
    eval {
        store( $self->{_corpus_doc_vectors}, $self->{_doc_vectors_db} );
    };
    if ($@) {
        print "Something went wrong with disk storage of document vectors: $@";
    }
}

sub display_doc_vectors {
    my $self = shift;
    die "document vectors not yet constructed" 
        unless keys %{$self->{_corpus_doc_vectors}};
    foreach my $file (sort keys %{$self->{_corpus_doc_vectors}}) {        
        print "\n\ndisplay doc vec for $file:\n";
        foreach ( sort keys %{$self->{_corpus_doc_vectors}->{$file}} ) {
            print "$_  =>   $self->{_corpus_doc_vectors}->{$file}->{$_}\n";
        }
        my $docvec_size = keys %{$self->{_corpus_doc_vectors}->{$file}};
        print "\nSize of vector for $file: $docvec_size\n";
    }
}

sub display_corpus_vocab {
    my $self = shift;
    die "corpus vocabulary not yet constructed"
        unless keys %{$self->{_vocab_hist}};
    print "\n\nDisplaying corpus vocabulary:\n\n";
    foreach (sort keys %{$self->{_vocab_hist}}){
        my $outstring = sprintf("%30s     %d", $_,$self->{_vocab_hist}->{$_});
        print "$outstring\n";
    }
    my $vocab_size = scalar( keys %{$self->{_vocab_hist}} );
    print "\nSize of the corpus vocabulary: $vocab_size\n\n";
}

sub retrieve_with_vsm {
    my $self = shift;
    my $query = shift;
    print "\nYour query words are: @$query\n" if $self->{_debug};
    die "\nYou need to first invoke get_corpus_vocabulary_and_word_counts()\n".
        "   and generate_document_vectors() before you can call\n" .
        "   retrieve_with_vsm()\n"
        unless scalar(keys %{$self->{_vocab_hist}}) 
              && scalar(keys %{$self->{_corpus_doc_vectors}});
    foreach ( keys %{$self->{_vocab_hist}} ) {        
        $self->{_query_vector}->{$_} = 0;    
    }
    foreach (@$query) {
        $self->{_query_vector}->{$_}++ if exists $self->{_vocab_hist}->{$_};
    }
    my @query_word_counts = values %{$self->{_query_vector}};
    my $query_word_count_total = reduce(\@query_word_counts);
    die "Query does not contain corpus words. Nothing retrieved.\n"
        unless $query_word_count_total;
    my %retrievals;
    foreach (sort {$self->_doc_vec_comparator} 
                     keys %{$self->{_corpus_doc_vectors}}) {
        $retrievals{$_} = $self->_similarity_to_query($_);
    }
    if ($self->{_debug}) {
        print "\n\nShowing the VSM retrievals and the similarity scores:\n\n";
        foreach (sort {$retrievals{$b} <=> $retrievals{$a}} keys %retrievals) {
            print "$_   =>   $retrievals{$_}\n";
        }
    }
    return \%retrievals;
}

sub upload_vsm_model_from_disk {
    my $self = shift;
    die "\nCannot find the database files for the VSM model"
        unless -s "$self->{_corpus_vocab_db}.pag" 
            && -s $self->{_doc_vectors_db};
    $self->{_corpus_doc_vectors} = retrieve($self->{_doc_vectors_db});
    tie %{$self->{_vocab_hist_on_disk}}, 'SDBM_File', 
                      $self->{_corpus_vocab_db}, O_RDONLY, 0640
            or die "Can't open DBM file: $!";       
    if ($self->{_debug}) {
        foreach ( sort keys %{$self->{_vocab_hist_on_disk}} ) {               
            printf( "%s\t%d\n", $_, $self->{_vocab_hist_on_disk}->{$_} );    
        }
    }
    foreach (keys %{$self->{_vocab_hist_on_disk}}) {
        $self->{_vocab_hist}->{$_} = $self->{_vocab_hist_on_disk}->{$_};
    }
    $self->{_corpus_vocab_done} = 1;
    $self->{_vocab_size} = scalar( keys %{$self->{_vocab_hist}} );
    print "\n\nVocabulary size:  $self->{_vocab_size}\n\n"
               if $self->{_debug};
    $self->{_corpus_doc_vectors} = retrieve($self->{_doc_vectors_db});
    untie %{$self->{_vocab_hist_on_disk}};
}

sub upload_lsa_model_from_disk {
    my $self = shift;
    die "\nCannot find the database files for the VSM model"
                unless -s "$self->{_corpus_vocab_db}.pag" 
                    && -s $self->{_doc_vectors_db} 
                    && -s $self->{_lsa_doc_vectors_db}; 
    $self->upload_vsm_model_from_disk();
    use PDL::IO::Storable;
    $self->{_doc_vecs_trunc_lsa} = retrieve($self->{_lsa_doc_vectors_db});
}

sub display_retrievals {
    my $self = shift;
    my $retrievals = shift;
    print "\n\nShowing the retrievals and the similarity scores:\n\n";
    my $iter = 0;
    foreach (sort {$retrievals->{$b} <=> $retrievals->{$a}} keys %$retrievals){
        print "$_   =>   $retrievals->{$_}\n"; 
        $iter++;
        last if $iter > $self->{_max_number_retrievals};
    }   
    print "\n\n";
}




sub _scan_directory {
    my $self = shift;
    my $dir = shift;
    chdir $dir or die "Unable to change directory to $dir: $!";
    $dir = cwd;
    foreach ( glob "*" ) {                                            
        if ( -d and !(-l) ) {
            $self->_scan_directory( $_ );
            chdir $dir                                                
                or die "Unable to change directory to $dir: $!";
        } elsif (-r _ and 
                 -T _ and 
                 -M _ > 0.00001 and  # modification age is at least 1 sec
                !( -l $_ ) and 
                !m{\.ps$} and 
                !m{\.pdf$} and 
                !m{\.eps$} and 
                !m{\.out$} and 
                !m{~$} ) {
            $self->_scan_file_for_rels($_) if $self->{_scan_dir_for_rels};
            $self->_scan_file($_) unless $self->{_corpus_vocab_done};
            $self->_construct_doc_vector($_) if $self->{_corpus_vocab_done};
        }
    }
}

sub _scan_file {
    my $self = shift;
    my $file = shift;
    open IN, $file;
    my $min = $self->{_min_word_length};
    while (<IN>) {
        chomp;                                                 
        my @clean_words = grep $_, map { /([a-z0-9_]{$min,})/i;$1 } split; 
        next unless @clean_words;
        @clean_words = grep $_, map &simple_stemmer($_), @clean_words
               if $self->{_want_stemming};
        map { $self->{_vocab_hist_on_disk}->{"\L$_"}++ } grep $_, @clean_words;
    }
    close( IN );
}

sub construct_lsa_model {
    my $self = shift;
    if (!$self->{_corpus_doc_vectors} and -s $self->{_doc_vectors_db}) { 
        $self->{_corpus_doc_vectors} = retrieve($self->{_doc_vectors_db});
    }
    foreach (sort keys %{$self->{_corpus_doc_vectors}}) {
        my $term_frequency_vec;
        foreach my $word (sort keys %{$self->{_corpus_doc_vectors}->{$_}}){
            push @$term_frequency_vec,   
                    $self->{_corpus_doc_vectors}->{$_}->{$word};
        }
        push @{$self->{_term_document_matrix}}, $term_frequency_vec;
    }
    use PDL;
    my $A = transpose( pdl(@{$self->{_term_document_matrix}}) );
    my ($U,$SIGMA,$V) = svd $A;
    print "LSA: Singular Values SIGMA: " . $SIGMA . "\n" if $self->{_debug};
    print "size of svd SIGMA:  ", $SIGMA->dims, "\n" if $self->{_debug};
    my $index = return_index_of_last_value_above_threshold($SIGMA, 
                                          $self->{_lsa_svd_threshold});
    my $SIGMA_trunc = $SIGMA->slice("0:$index")->sever;
    print "SVD's Trucated SIGMA: " . $SIGMA_trunc . "\n" if $self->{_debug};

    # When you measure the size of a matrix in PDL, the zeroth dimension
    # is considered to be along the horizontal and the one-th dimension
    # along the rows.  This is the opposite of how we want to look at
    # matrices.  For a matrix of size MxN, we mean M rows and N columns.
    # With this 'rows x columns' convention for matrix size, if you had
    # check the size of, say, U matrix, you would call
#    my @size = ( $U->getdim(1), $U->getdim(0) );
#    print "\nsize of U: @size\n";

    my $U_trunc = $U->slice("0:$index,:")->sever;
    my $V_trunc = $V->slice("0:$index,0:$index")->sever;    
    $self->{_lsa_vec_truncator} = inv(stretcher($SIGMA_trunc)) x 
                                             transpose($U_trunc);
    print "\n\nLSA doc truncator: " . $self->{_lsa_vec_truncator} . "\n\n" 
            if $self->{_debug};
    my @sorted_doc_names = sort keys %{$self->{_corpus_doc_vectors}};
    my $i = 0;
    foreach (@{$self->{_term_document_matrix}}) {
        my $truncated_doc_vec = $self->{_lsa_vec_truncator} x 
                                               transpose(pdl($_));
        my $doc_name = $sorted_doc_names[$i++];
        print "\n\nTruncated doc vec for $doc_name: " . 
                 $truncated_doc_vec . "\n" if $self->{_debug};
        $self->{_doc_vecs_trunc_lsa}->{$doc_name} 
                                                 = $truncated_doc_vec;
    }
    chdir $self->{_working_directory};
    eval {
        use PDL::IO::Storable;
        store( $self->{_doc_vecs_trunc_lsa}, $self->{_lsa_doc_vectors_db} );
    };
    if ($@) {
        print "Something went wrong with disk storage of lsa doc vectors: $@";
    }
}

sub retrieve_with_lsa {
    use PDL;
    my $self = shift;
    my $query = shift;
    print "\nYour query words are: @$query\n" if $self->{_debug};
    die "You must first construct an LSA model" 
        unless scalar(keys %{$self->{_doc_vecs_trunc_lsa}});
    foreach ( keys %{$self->{_vocab_hist}} ) {        
        $self->{_query_vector}->{$_} = 0;    
    }
    foreach (@$query) {
        $self->{_query_vector}->{$_}++ if exists $self->{_vocab_hist}->{$_};
    }
    my @query_word_counts = values %{$self->{_query_vector}};
    my $query_word_count_total = reduce(\@query_word_counts);
    die "Query does not contain corpus words. Nothing retrieved.\n"
        unless $query_word_count_total;
    my $query_vec;
    foreach (sort keys %{$self->{_query_vector}}) {
        push @$query_vec, $self->{_query_vector}->{$_};
    }
    print "\n\nQuery vector: @$query_vec\n" if $self->{_debug};
    my $truncated_query_vec = $self->{_lsa_vec_truncator} x 
                                               transpose(pdl($query_vec));
    print "\n\nTruncated query vector: " .  $truncated_query_vec . "\n"
                                   if $self->{_debug};                  
    my %retrievals;
    foreach (sort keys %{$self->{_doc_vecs_trunc_lsa}}) {
        my $dot_product = transpose($truncated_query_vec)
                     x pdl($self->{_doc_vecs_trunc_lsa}->{$_});
        print "\n\nLSA: dot product of truncated query and\n" .
              "     truncated vec for doc $_ is " . $dot_product->sclr . "\n"
                                        if $self->{_debug};                  
        $retrievals{$_} = $dot_product->sclr;
    }
    if ($self->{_debug}) {
        print "\n\nShowing LSA retrievals and similarity scores:\n\n";
        foreach (sort {$retrievals{$b} <=> $retrievals{$a}} keys %retrievals) {
            print "$_   =>   $retrievals{$_}\n";
        }
        print "\n\n";
    }
    return \%retrievals;
}

sub _construct_doc_vector {
    my $self = shift;
    my $file = shift;
    my %document_vector = %{deep_copy_hash($self->{_doc_hist_template})};
    foreach ( sort keys %{$self->{_doc_hist_template}} ) {  
        $document_vector{$_} = 0;    
    }
    my $min = $self->{_min_word_length};
    unless (open IN, $file) {
        print "Unable to open file $file in the corpus: $!\n" 
            if $self->{_debug};
        return;
    }
    while (<IN>) {
        chomp;                                                    
        my @clean_words = grep $_, map { /([a-z0-9_]{$min,})/i;$1 } split; 
        next unless @clean_words;
        @clean_words = grep $_, 
                       map &simple_stemmer($_, $self->{_debug}), @clean_words
               if $self->{_want_stemming};
        map { $document_vector{$_}++ } 
                grep {exists $self->{_vocab_hist}->{$_}} @clean_words; 
    }
    close IN;
    die "Something went wrong. Doc vector size unequal to vocab size"
        unless $self->{_vocab_size} == scalar(keys %document_vector);
    my $pwd = cwd;
    $pwd =~ m{$self->{_corpus_directory}.?(\S*)$};
    my $file_path_name;
    unless ( $1 eq "" ) {
        $file_path_name = "$1/$file";
    } else {
        $file_path_name = $file;
    }
    $self->{_corpus_doc_vectors}->{$file_path_name} = \%document_vector;
}

sub _drop_stop_words {
    my $self = shift;
    open( IN, "$self->{_working_directory}/$self->{_stop_words_file}")
                     or die "unable to open stop words file: $!";
    while (<IN>) {
        next if /^#/;
        next if /^[ ]*$/;
        chomp;
        delete $self->{_vocab_hist_on_disk}->{$_} 
                if exists $self->{_vocab_hist_on_disk}->{$_};
        unshift @{$self->{_stop_words}}, $_;
    }
}

sub _doc_vec_comparator {
    my $self = shift;
    my %query_vector = %{$self->{_query_vector}};
    my $vec1_hash_ref = $self->{_corpus_doc_vectors}->{$a};
    my $vec2_hash_ref = $self->{_corpus_doc_vectors}->{$b};
    my @vec1 = ();
    my @vec2 = ();
    my @qvec = ();
    foreach my $word (sort keys %{$self->{_vocab_hist}}) {
        push @vec1, $vec1_hash_ref->{$word};
        push @vec2, $vec2_hash_ref->{$word};
        push @qvec, $query_vector{$word};
    }
    my $vec1_mag = vec_magnitude(\@vec1);
    my $vec2_mag = vec_magnitude(\@vec2);
    my $qvec_mag = vec_magnitude(\@qvec);
    my $product1 = vec_scalar_product(\@vec1, \@qvec);
    $product1 /= $vec1_mag * $qvec_mag;
    my $product2 = vec_scalar_product(\@vec2, \@qvec);
    $product2 /= $vec2_mag * $qvec_mag;
    return 1 if $product1 < $product2;
    return 0  if $product1 == $product2;
    return -1  if $product1 > $product2;
}

sub _similarity_to_query {
    my $self = shift;
    my $doc_name = shift;
    my $vec_hash_ref = $self->{_corpus_doc_vectors}->{$doc_name};
    my @vec = ();
    my @qvec = ();
    foreach my $word (sort keys %$vec_hash_ref) {
        push @vec, $vec_hash_ref->{$word};
        push @qvec, $self->{_query_vector}->{$word};
    }
    my $vec_mag = vec_magnitude(\@vec);
    my $qvec_mag = vec_magnitude(\@qvec);
    my $product = vec_scalar_product(\@vec, \@qvec);
    $product /= $vec_mag * $qvec_mag;
    return $product;
}


##############  Relevance Judgments for Testing Purposes   ###############

## IMPORTANT: This estimation of document relevancies to queries is NOT for
##            serious work.  A document is considered to be relevant to a
##            query if it contains several of the query words.  As to the
##            minimum number of query words that must exist in a document
##            in order for the latter to be considered relevant is
##            determined by the relevancy_threshold parameter in the VSM
##            constructor.  (See the relevancy and precision-recall related
##            scripts in the 'examples' directory.)  The reason for why the
##            function shown below is not for serious work is because
##            ultimately it is the humans who are the best judges of the
##            relevancies of documents to queries.  The humans bring to
##            bear semantic considerations on the relevancy determination
##            problem that are beyond the scope of this module.

sub estimate_doc_relevancies {
    my $self = shift;
    $self->{_query_file} = shift;
    open( IN, $self->{_query_file} )
               or die "unable to open the query file $self->{_query_file}: $!";
    croak "\n\nYou need to specify a name for the relevancy file in \n" .
        " in which the relevancy judgments will be dumped." 
                                 unless  $self->{_relevancy_file};
    while (<IN>) {
        chomp;
        next if /^#/;
        next if /^[ ]*$/;
        die "Format of query file is not correct" unless /^[ ]*q[0-9]+:/;
        /^[ ]*(q[0-9]+):[ ]*(.*)/;
        my $query_label = $1;
        my $query = $2;
        next unless $query;
        $self->{_queries_for_relevancy}->{$query_label} =  $query;
    }
    if ($self->{_debug}) {
        foreach (sort keys %{$self->{_queries_for_relevancy}}) {
            print "$_   =>   $self->{_queries_for_relevancy}->{$_}\n"; 
        }
    }
    $self->{_scan_dir_for_rels} = 1;
    $self->_scan_directory($self->{_corpus_directory});
    $self->{_scan_dir_for_rels} = 0;
    chdir $self->{_working_directory};
    open(OUT, ">$self->{_relevancy_file}") 
       or die "unable to open the relevancy file $self->{_relevancy_file}: $!";
    my @relevancy_list_for_query;
    foreach (sort 
               {get_integer_suffix($a) <=> get_integer_suffix($b)} 
               keys %{$self->{_relevancy_estimates}}) {    
        @relevancy_list_for_query = 
                        keys %{$self->{_relevancy_estimates}->{$_}};
        print OUT "$_   =>   @relevancy_list_for_query\n\n"; 
        print "\n\nNumber of relevant docs for query $_: " . 
                         scalar(@relevancy_list_for_query) . "\n\n";
    }
}

#   If there are available human-supplied relevancy judgments in a disk
#   file, use this script to upload that information.  One of the scripts
#   in the 'examples' directory carries out the precision-recall analysis 
#   by using this approach.  IMPORTANT:  The human-supplied relevancy
#   judgments must be in a format that is shown in the sample file
#   relevancy.txt in the 'examples' directory.
sub upload_document_relevancies_from_file {
    my $self = shift;
    chdir $self->{_working_directory};
    open( IN, $self->{_relevancy_file} )
       or die "unable to open the relevancy file $self->{_relevancy_file}: $!";
    while (<IN>) {
        chomp;
        next if /^#/;
        next if /^[ ]*$/;
        die "Format of query file is not correct" unless /^[ ]*q[0-9]+[ ]*=>/;
        /^[ ]*(q[0-9]+)[ ]*=>[ ]*(.*)/;
        my $query_label = $1;
        my $relevancy_docs_string = $2;
        next unless $relevancy_docs_string;
        my @relevancy_docs  =  grep $_, split / /, $relevancy_docs_string;
        my %relevancies =     map {$_ => 1} @relevancy_docs;
        $self->{_relevancy_estimates}->{$query_label} = \%relevancies;
    }
    if ($self->{_debug}) {
        for (sort keys %{$self->{_relevancy_estimates}}) {
            my @rels = keys %{$self->{_relevancy_estimates}->{$_}};
            print "$_   =>   @rels\n";
        }
    }
}

sub display_doc_relevancies {
    my $self = shift;
    die "You must first estimate or provide the doc relevancies" 
        unless scalar(keys %{$self->{_relevancy_estimates}});
    print "\nDisplaying relevancy judgments:\n\n";
    foreach my $query (sort keys %{$self->{_relevancy_estimates}}) {
        print "Query $query\n";
        foreach my $file (sort {
                          $self->{_relevancy_estimates}->{$query}->{$b}
                          <=>
                          $self->{_relevancy_estimates}->{$query}->{$a}
                          }
            keys %{$self->{_relevancy_estimates}->{$query}}){
            print "     $file  => $self->{_relevancy_estimates}->{$query}->{$file}\n";
        }
    }
}

sub _scan_file_for_rels {
    my $self = shift;
    my $file = shift;
    open IN, $file;
    my @all_text = <IN>;
    @all_text = grep $_, map {s/[\r]?\n$//; $_;} @all_text;
    my $all_text = join ' ', @all_text;
    foreach my $query (sort keys %{$self->{_queries_for_relevancy}}) {
        my $count = 0;
        my @query_words = grep $_, 
                split /\s+/, $self->{_queries_for_relevancy}->{$query};
        print "Query words for $query:   @query_words\n" if $self->{_debug};
        foreach my $word (@query_words) {
            my @matches = $all_text =~ /$word/gi;
            print "Number of occurrences for word '$word' in file $file: " . 
                scalar(@matches) . "\n" if $self->{_debug};
            $count += @matches if @matches;         
        }
        print "\nRelevancy count for query $query and file $file: $count\n\n"
            if $self->{_debug};
        $self->{_relevancy_estimates}->{$query}->{$file} = $count 
            if $count >= $self->{_relevancy_threshold};
    }
}


#################   Calculate Precision versus Recall   ####################

sub precision_and_recall_calculator {
    my $self = shift;
    my $retrieval_type = shift;
    die "You must first estimate or provide the doc relevancies" 
        unless scalar(keys %{$self->{_relevancy_estimates}});
    unless (scalar(keys %{$self->{_queries_for_relevancy}})) {
        open( IN, $self->{_query_file})
               or die "unable to open the query file $self->{_query_file}: $!";
        while (<IN>) {
            chomp;
            next if /^#/;
            next if /^[ ]*$/;
            die "Format of query file is not correct" unless /^[ ]*q[0-9]+:/;
            /^[ ]*(q[0-9]+):[ ]*(.*)/;
            my $query_label = $1;
            my $query = $2;
            next unless $query;
            $self->{_queries_for_relevancy}->{$query_label} =  $query;
        }
        if ($self->{_debug}) {
            print "\n\nDisplaying queries in the query file:\n\n";
            foreach (sort keys %{$self->{_queries_for_relevancy}}) {
                print "$_   =>   $self->{_queries_for_relevancy}->{$_}\n"; 
            }
        }
    }
    foreach my $query (sort keys %{$self->{_queries_for_relevancy}}) {
        print "\n\n\nQuery $query:\n" if $self->{_debug};
        my @query_words = grep $_, 
                split /\s+/, $self->{_queries_for_relevancy}->{$query};
        my $retrievals;
        croak "\n\nYou have not specified the retrieval type for " . 
              "precision-recall calculation.  See code in 'examples'" .
              "directory:" if !defined $retrieval_type;
        if ($retrieval_type eq 'vsm') {
            $retrievals = $self->retrieve_with_vsm( \@query_words );
        } elsif ($retrieval_type eq 'lsa') {
            $retrievals = $self->retrieve_with_lsa( \@query_words );
        }
        my %ranked_retrievals;
        my $i = 1;
        foreach (sort {$retrievals->{$b} <=> $retrievals->{$a}} 
                                                      keys %$retrievals) {
            $ranked_retrievals{$i++} = $_;
        }      
        if ($self->{_debug}) {
            print "\n\nDisplaying ranked retrievals for query $query:\n\n";
            foreach (sort {$a <=> $b} keys %ranked_retrievals) {
                print "$_  =>   $ranked_retrievals{$_}\n";   
            }      
        }
        #   At this time, ranking of relevant documents based on their
        #   relevancy counts serves no particular purpose since all we want
        #   for the calculation of Precision and Recall are the total
        #   number of relevant documents.  However, I believe such a
        #   ranking will play an important role in the future.
        #   IMPORTANT:  The relevancy judgments are ranked only when
        #               estimated by the method estimate_doc_relevancies()
        #               of the VSM class.  When relevancies are supplied
        #               directly through a disk file, they all carry the
        #               same rank.
        my %ranked_relevancies;
        $i = 1;
        foreach my $file (sort {
                          $self->{_relevancy_estimates}->{$query}->{$b}
                          <=>
                          $self->{_relevancy_estimates}->{$query}->{$a}
                          }
                          keys %{$self->{_relevancy_estimates}->{$query}}) {
            $ranked_relevancies{$i++} = $file;
        }
        if ($self->{_debug}) {
            print "\n\nDisplaying ranked relevancies for query $query:\n\n";
            foreach (sort {$a <=> $b} keys %ranked_relevancies) {
                print "$_  =>   $ranked_relevancies{$_}\n";   
            }      
        }
        my @relevant_set = values %ranked_relevancies;

        warn "\n\nNo relevant docs found for query $query.\n" .
             "Will skip over this query for precision and\n" .
             "recall calculations\n\n" unless @relevant_set;
        next unless @relevant_set;    
        print "\n\nRelevant set for query $query:  @relevant_set\n\n"
            if $self->{_debug};
        my @retrieved;
        foreach (sort keys %ranked_retrievals) {
            push @retrieved, $ranked_retrievals{$_};
        }
        print "\n\nRetrieved set for query $query: @retrieved\n\n"
            if $self->{_debug};
        my @Precision_values = ();
        my @Recall_values = ();
        my $rank = 1;
        while ($rank < @retrieved + 1) {
            my $index = 1;      
            my @retrieved_at_rank = ();
            while ($index <= $rank) {
                push @retrieved_at_rank, $ranked_retrievals{$index};
                $index++;
            }
            my $intersection =set_intersection(\@retrieved_at_rank,
                                               \@relevant_set);
            my $precision_at_rank = @retrieved_at_rank ? 
                                 (@$intersection / @retrieved_at_rank) : 0;
            push @Precision_values, $precision_at_rank;
            my $recall_at_rank = @$intersection / @relevant_set;
            push @Recall_values, $recall_at_rank;
            $rank++;
        }
        print "\n\nFor query $query, precision values: @Precision_values\n"
            if $self->{_debug};
        print "\nFor query $query, recall values: @Recall_values\n"
            if $self->{_debug};      
        $self->{_precision_for_queries}->{$query} = \@Precision_values;
        $self->{_recall_for_queries}->{$query} = \@Recall_values;
        my $area = 0;
        #  Use trapezoidal rule to find the area under the precision-recall
        #  curve:
        for my $j (1..@Precision_values-1) {
            my $height = ($Precision_values[$j]+$Precision_values[$j-1])/2.0;
            my $base = ($Recall_values[$j] - $Recall_values[$j-1]);
            $area += $base * $height;
        }
        my $map_for_query = $area;
        print "\nMAP for query $query: $map_for_query\n" if $self->{_debug};
        $self->{_map_vals_for_queries}->{$query} = $map_for_query;
    }
}

sub display_map_values_for_queries {
    my $self = shift;
    die "You must first invoke precision_and_recall_calculator function" 
        unless scalar(keys %{$self->{_map_vals_for_queries}});
    my $map = 0;
    print "\n\nDisplaying average precision for different queries:\n\n";
    foreach my $query (sort 
                         {get_integer_suffix($a) <=> get_integer_suffix($b)} 
                         keys %{$self->{_map_vals_for_queries}}) {
        my $output = sprintf "Query %s  =>   %.3f", 
                 $query, $self->{_map_vals_for_queries}->{$query};
        print "$output\n";
        $map += $self->{_map_vals_for_queries}->{$query};
    }
    print "\n\n";
    my $avg_map_for_all_queries = 
                $map / scalar(keys %{$self->{_map_vals_for_queries}});
    print "MAP value: $avg_map_for_all_queries\n\n";
}

sub display_precision_vs_recall_for_queries {
    my $self = shift;
    die "You must first invoke precision_and_recall_calculator function" 
        unless scalar(keys %{$self->{_precision_for_queries}});
    print "\n\nDisplaying precision and recall values for different queries:\n\n";
    foreach my $query (sort 
                         {get_integer_suffix($a) <=> get_integer_suffix($b)} 
                         keys %{$self->{_map_vals_for_queries}}) {
        print "\n\nQuery $query:\n";
        print "\n   (The first value is for rank 1, the second value at rank 2, and so on.)\n\n";
        my @precision_vals = @{$self->{_precision_for_queries}->{$query}};
        @precision_vals = map {sprintf "%.3f", $_} @precision_vals;
        print "   Precision at rank  =>  @precision_vals\n";
        my @recall_vals = @{$self->{_recall_for_queries}->{$query}};
        @recall_vals = map {sprintf "%.3f", $_} @recall_vals;
        print "\n   Recall at rank   =>  @recall_vals\n";
    }
    print "\n\n";
}

###########################  Utility Routines  #####################

sub _check_for_illegal_params {
    my @params = @_;
    my @legal_params = qw / corpus_directory
                            corpus_vocab_db
                            doc_vectors_db
                            lsa_doc_vectors_db
                            stop_words_file
                            max_number_retrievals
                            query_file
                            relevancy_file
                            min_word_length
                            want_stemming
                            lsa_svd_threshold
                            relevancy_threshold
                            debug
                          /;
    my $found_match_flag;
    foreach my $param (@params) {
        foreach my $legal (@legal_params) {
            $found_match_flag = 0;
            if ($param eq $legal) {
                $found_match_flag = 1;
                last;
            }
        }
        last if $found_match_flag == 0;
    }
    return $found_match_flag;
}

# Meant only for an un-nested hash:
sub deep_copy_hash {
    my $ref_in = shift;
    my $ref_out = {};
    foreach ( keys %{$ref_in} ) {
        $ref_out->{$_} = $ref_in->{$_};
    }
    return $ref_out;
}

sub vec_scalar_product {
    my $vec1 = shift;
    my $vec2 = shift;
    croak "Something is wrong --- the two vectors are of unequal length"
        unless @$vec1 == @$vec2;
    my $product;
    for my $i (0..@$vec1-1) {
        $product += $vec1->[$i] * $vec2->[$i];
    }
    return $product;
}

sub vec_magnitude {
    my $vec = shift;
    my $mag_squared = 0;
    foreach my $num (@$vec) {
        $mag_squared += $num ** 2;
    }
    return sqrt $mag_squared;
}

sub reduce {
    my $vec = shift;
    my $result;
    for my $item (@$vec) {
        $result += $item;
    }
    return $result;
}

sub simple_stemmer {
    my $word = shift;
    my $debug = shift;
    print "\nStemming the word:        $word\n" if $debug;
    $word =~ s/(.*[a-z][^aeious])s$/$1/i;
    $word =~ s/(.*[a-z]s)es$/$1/i;
    $word =~ s/(.*[a-z][ck])es$/$1e/i;
    $word =~ s/(.*[a-z]+)tions$/$1tion/i;
    $word =~ s/(.*[a-z]+)mming$/$1m/i;
    $word =~ s/(.*[a-z]+[^rl])ing$/$1/i;
    $word =~ s/(.*[a-z]+o[sn])ing$/$1e/i;
    $word =~ s/(.*[a-z]+)tices$/$1tex/i;
    $word =~ s/(.*[a-z]+)pes$/$1pe/i;
    $word =~ s/(.*[a-z]+)sed$/$1se/i;
    $word =~ s/(.*[a-z]+)ed$/$1/i;
    $word =~ s/(.*[a-z]+)tation$/$1t/i;
    print "Stemmed word:                           $word\n\n" if $debug;
    return $word;
}

# Assumes the array is sorted in a descending order, as would be the
# case with an array of singular values produced by an SVD algorithm
sub return_index_of_last_value_above_threshold {
    my $pdl_obj = shift;
    my $size = $pdl_obj->getdim(0);
    my $threshold = shift;
    my $lower_bound = $pdl_obj->slice(0)->sclr * $threshold;
    my $i = 0;
    while ($i < $size && $pdl_obj->slice($i)->sclr > $lower_bound) {$i++;}
    return $i-1;
}

sub set_intersection {
    my $set1 = shift;
    my $set2 = shift;
    my %hset1 = map {$_ => 1} @$set1;
    my  @common_elements = grep {$hset1{$_}} @$set2;
    return @common_elements ? \@common_elements : [];
}

sub get_integer_suffix {
    my $label = shift;
    $label =~ /(\d*)$/;
    return $1;
}

1;

=pod
=head1 NAME

Algorithm::VSM --- A pure-Perl implementation for constructing a Vector
Space Model (VSM) or a Latent Semantic Analysis Model (LSA) of a software
library and for using such a model for efficient retrieval of files in
response to search words.

=head1 SYNOPSIS

  # FOR CONSTRUCTING A VSM MODEL FOR RETRIEVAL:

        use Algorithm::VSM;

        my $corpus_dir = "corpus";
        my @query = qw/ program listiterator add arraylist args /;
        my $stop_words_file = "stop_words.txt";  
        my $corpus_vocab_db = "corpus_vocab_db";
        my $doc_vectors_db  = "doc_vectors_db"; 
        my $vsm = Algorithm::VSM->new( 
                           corpus_directory         => $corpus_dir,
                           corpus_vocab_db          => $corpus_vocab_db,
                           doc_vectors_db           => $doc_vectors_db, 
                           stop_words_file          => $stop_words_file,
                           max_number_retrievals    => 10,
                           want_stemming            => 1,  
        #                  debug                    => 1,
        );
        $vsm->get_corpus_vocabulary_and_word_counts();
        $vsm->generate_document_vectors();
        $vsm->display_corpus_vocab();
        $vsm->display_doc_vectors();
        my $retrievals = $vsm->retrieve_for_query_with_vsm( \@query );
        $vsm->display_retrievals( $retrievals );

     The constructor parameter 'corpus_directory' is for naming the root of
     the directory whose VSM model you wish to construct.  The parameters
     'corpus_vocab_db' and 'doc_vectors_db' are for naming disk-based
     databases in which the VSM model will be stored.  Subsequently, these
     databases can be used for much faster retrieval from the same corpus.
     The parameter 'want_stemming' means that you would want the words in
     the documents to be stemmed to their root forms before the VSM model
     is constructed.  Stemming will reduce all words such as 'programming,'
     'programs,' 'program,' etc. to the same root word 'program.'

     The functions display_corpus_vocab() and display_doc_vectors() are
     there only for testing purposes with small corpora.  If you must use
     them for large libraries/corpora, you might wish to redirect the
     output to a file.  The 'debug' option, when turned on, will output a
     large number of intermediate results in the calculation of the model.
     It is best to redirect the output to a file if 'debug' is on.



  # FOR CONSTRUCTING AN LSA MODEL FOR RETRIEVAL:

        my $corpus_dir = "corpus";
        my @query = qw/ program listiterator add arraylist args /;
        my $stop_words_file = "stop_words.txt";
        my $vsm = Algorithm::VSM->new( 
                           corpus_directory         => $corpus_dir,
                           corpus_vocab_db          => $corpus_vocab_db,
                           doc_vectors_db           => $doc_vectors_db,
                           lsa_doc_vectors_db       => $lsa_doc_vectors_db,
                           stop_words_file          => $stop_words_file,
                           want_stemming            => 1,
                           lsa_svd_threshold        => 0.01, 
                           max_number_retrievals    => 10,
        #                  debug                    => 1,
        );
        $vsm->get_corpus_vocabulary_and_word_counts();
        $vsm->generate_document_vectors();
        $vsm->display_corpus_vocab();           # only on a small corpus
        $vsm->display_doc_vectors();            # only on a small corpus
        $vsm->construct_lsa_model();
        my $retrievals = $vsm->retrieve_for_query_with_lsa( \@query );
        $vsm->display_retrievals( $retrievals );

    In the calls above, the constructor parameter lsa_svd_threshold
    determines how many of the singular values will be retained after we
    have carried out an SVD decomposition of the term-frequency matrix for
    the documents in the corpus.  Singular values smaller than this
    threshold fraction of the largest value are rejected.  The parameters
    that end in '_db' are for naming the database files in which the LSA
    model will be stored.  We have already mentioned the role played by the
    parameters 'corpus_vocab_db,' and 'doc_vectors_db (see the explanation
    that goes with the previous construct call example).  The database
    related parameter 'lsa_doc_vectors_db' is for naming the file in which
    we will store the reduced-dimensionality document vectors for the LSA
    model.  This would allow fast LSA-based search to be carried out
    subsequently.



  # FOR USING A PREVIOUSLY CONSTRUCTED VSM MODEL FOR RETRIEVAL:

        my @query = qw/ program listiterator add arraylist args /;
        my $corpus_vocab_db = "corpus_vocab_db";
        my $doc_vectors_db  = "doc_vectors_db";
        my $vsm = Algorithm::VSM->new( 
                           corpus_vocab_db           => $corpus_vocab_db, 
                           doc_vectors_db            => $doc_vectors_db,
                           max_number_retrieval s    => 10,
        #                  debug                     => 1,
        );
        $vsm->upload_vsm_model_from_disk();
        $vsm->display_corpus_vocab();            # only on a small corpus
        $vsm->display_doc_vectors();             # only on a small corpus
        my $retrievals = $vsm->retrieve_with_vsm( \@query );
        $vsm->display_retrievals( $retrievals );



  # FOR USING A PREVIOUSLY CONSTRUCTED LSA MODEL FOR RETRIEVAL:

        my @query = qw/ program listiterator add arraylist args /;
        my $corpus_vocab_db = "corpus_vocab_db";
        my $doc_vectors_db  = "doc_vectors_db";
        my $lsa_doc_vectors_db = "lsa_doc_vectors_db";
        my $vsm = Algorithm::VSM->new( 
                           corpus_vocab_db          => $corpus_vocab_db,
                           doc_vectors_db           => $doc_vectors_db,
                           lsa_doc_vectors_db       => $lsa_doc_vectors_db,
                           max_number_retrievals    => 10,
        #                  debug               => 1,
        );
        $vsm->upload_lsa_model_from_disk();
        $vsm->display_corpus_vocab();          # only on a small corpus
        $vsm->display_doc_vectors();           # only on a small corpus 
        $vsm->construct_lsa_model();
        my $retrievals = $vsm->retrieve_with_lsa( \@query );
        $vsm->display_retrievals( $retrievals );



  # FOR MEASURING PRECISION VERSUS RECALL FOR VSM:

        my $corpus_dir = "corpus";   
        my $stop_words_file = "stop_words.txt";  
        my $query_file      = "test_queries.txt";  
        my $relevancy_file   = "relevancy.txt";   # All relevancy judgments
                                                  # will be stored in this file
        my $vsm = Algorithm::VSM->new( 
                           corpus_directory    => $corpus_dir,
                           stop_words_file     => $stop_words_file,
                           query_file          => $query_file,
                           want_stemming       => 1,
                           relevancy_threshold => 5, 
                           relevancy_file      => $relevancy_file, 
        #                  debug               => 1,
        );

        $vsm->get_corpus_vocabulary_and_word_counts();
        $vsm->generate_document_vectors();
        $vsm->estimate_doc_relevancies("test_queries.txt");
        $vsm->display_corpus_vocab();                  # used only for testing
        $vsm->display_doc_relevancies();               # used only for testing
        $vsm->precision_and_recall_calculator('vsm');
        $vsm->display_precision_vs_recall_for_queries();
        $vsm->display_map_values_for_queries();

      Measuring precision and recall requires a set of queries.  These are
      supplied through the constructor parameter 'query_file'.  The format
      of the this file must be according to the sample file
      'test_queries.txt' in the 'examples' directory.  The module estimates
      the relevancies of the documents to the queries and dumps the
      relevancies in a file named by the 'relevancy_file' constructor
      parameter.  The constructor parameter 'relevancy_threshold' is used
      in deciding which of the documents are considered to be relevant to a
      query.  A document must contain at least the 'relevancy_threshold'
      occurrences of query words in order to be considered relevant to a
      query.



  # FOR MEASURING PRECISION VERSUS RECALL FOR LSA:

        my $corpus_dir = "corpus";    
        my $stop_words_file = "stop_words.txt";  
        my $query_file      = "test_queries.txt"; 
        my $relevancy_file   = "relevancy.txt";  

        my $vsm = Algorithm::VSM->new( 
                           corpus_directory    => $corpus_dir,
                           stop_words_file     => $stop_words_file,
                           query_file          => $query_file,
                           want_stemming       => 1,
                           lsa_svd_threshold   => 0.01,
                           relevancy_threshold => 5,
                           relevancy_file      => $relevancy_file,
        #                   debug               => 1,
        );

        $vsm->get_corpus_vocabulary_and_word_counts();
        $vsm->generate_document_vectors();
        $vsm->construct_lsa_model();
        $vsm->estimate_doc_relevancies("test_queries.txt");
        $vsm->display_doc_relevancies();
        $vsm->precision_and_recall_calculator('lsa');
        $vsm->display_precision_vs_recall_for_queries();
        $vsm->display_map_values_for_queries();

      We have already explained the purpose of the constructor parameter
      'query_file' and about the constraints on the format of queries in
      the file named through this parameter.  As mentioned earlier, the
      module estimates the relevancies of the documents to the queries and
      dumps the relevancies in a file named by the 'relevancy_file'
      constructor parameter.  The constructor parameter
      'relevancy_threshold' is used in deciding which of the documents are
      considered to be relevant to a query.  A document must contain at
      least the 'relevancy_threshold' occurrences of query words in order
      to be considered relevant to a query.  We have previously explained
      the role of the constructor parameter 'lsa_svd_threshold'.


  # FOR MEASURING PRECISION VERSUS RECALL FOR VSM USING FILE-BASED RELEVANCE JUDGMENTS:

        my $corpus_dir = "corpus";  
        my $stop_words_file = "stop_words.txt";
        my $query_file      = "test_queries.txt";
        my $relevancy_file   = "relevancy.txt";  

        my $vsm = Algorithm::VSM->new( 
                   corpus_directory    => $corpus_dir,
                   stop_words_file     => $stop_words_file,
                   query_file          => $query_file,
                   want_stemming       => 1,
                   relevancy_file      => $relevancy_file,
        #        debug               => 1,
        );

        $vsm->get_corpus_vocabulary_and_word_counts();
        $vsm->generate_document_vectors();
        $vsm->upload_document_relevancies_from_file();  
        $vsm->display_doc_relevancies();
        $vsm->precision_and_recall_calculator('vsm');
        $vsm->display_precision_vs_recall_for_queries();
        $vsm->display_map_values_for_queries();

    Now the filename supplied through the constructor parameter
    'relevancy_file' must contain relevance judgments for the queries that
    are named in the file supplied through the parameter 'query_file'.  The
    format of these two files must be according to what is shown in the
    sample files 'test_queries.txt' and 'relevancy.txt' in the 'examples'
    directory.



  # FOR MEASURING PRECISION VERSUS RECALL FOR LSA USING FILE-BASED RELEVANCE JUDGMENTS:

        my $corpus_dir = "corpus";  
        my $stop_words_file = "stop_words.txt";
        my $query_file      = "test_queries.txt";
        my $relevancy_file   = "relevancy.txt";  

        my $vsm = Algorithm::VSM->new( 
                   corpus_directory    => $corpus_dir,
                   corpus_vocab_db     => $corpus_vocab_db,
                   doc_vectors_db      => $doc_vectors_db,
                   stop_words_file     => $stop_words_file,
                   query_file          => $query_file,
                   want_stemming       => 1,
                   lsa_svd_threshold   => 0.01,
                   relevancy_file      => $relevancy_file,
        #        debug               => 1,
        );

        $vsm->get_corpus_vocabulary_and_word_counts();
        $vsm->generate_document_vectors();
        $vsm->display_corpus_vocab();
        $vsm->display_doc_vectors();
        $vsm->upload_document_relevancies_from_file();  
        $vsm->display_doc_relevancies();
        $vsm->precision_and_recall_calculator('vsm');
        $vsm->display_precision_vs_recall_for_queries();
        $vsm->display_map_values_for_queries();

    As mentioned for the previous code block, the filename supplied through
    the constructor parameter 'relevancy_file' must contain relevance
    judgments for the queries that are named in the file supplied through
    the parameter 'query_file'.  The format of this file must be according
    to what is shown in the sample file 'relevancy.txt' in the 'examples'
    directory.  We have already explained the roles played by the
    constructor parameters such as 'lsa_svd_threshold'.


=head1 DESCRIPTION

B<Algorithm::VSM> is a I<perl5> module for constructing a Vector Space
Model (VSM) or a Latent Semantic Analysis Model (LSA) of a collection of
documents, usually referred to as a corpus, and then retrieving the
documents in response to search words in a query.

VSM and LSA models have been around for a long time in the Information
Retrieval (IR) community.  More recently such models have been shown to be
effective in retrieving files/documents from software libraries. For an
account of this research that was presented by Shivani Rao and the author
of this module at the 2011 Mining Software Repositories conference, see
L<http://portal.acm.org/citation.cfm?id=1985451>.

VSM modeling consists of: (1) Extracting the vocabulary used in a corpus.
(2) Stemming the words so extracted and eliminating the designated stop
words from the vocabulary.  Stemming means that closely related words like
'programming' and 'programs' are reduced to the common root word 'program'
and the stop words are the non-discriminating words that can be expected to
exist in virtually all the documents. (3) Constructing document vectors for
the individual files in the corpus --- the document vectors taken together
constitute what is usually referred to as a 'term-frequency' matrix for the
corpus. (4) Constructing a query vector for the search query after the
query is subject to the same stemming and stop-word elimination rules that
were applied to the corpus. And, lastly, (5) Using a similarity metric to
return the set of documents that are most similar to the query vector.  The
commonly used similarity metric is one based on the cosine distance between
two vectors.  Also note that all the vectors mentioned here are of the same
size, the size of the vocabulary extracted from the corpus.  An element of
a vector is the frequency of the occurrence of the word corresponding to
that position in the vector.

LSA modeling is a small variation on VSM modeling.  Now you take VSM
modeling one step further by subjecting the term-frequency matrix for the
corpus to singular value decomposition (SVD).  By retaining only a subset
of the singular values (usually the N largest for some value of N), you can
construct reduced-dimensionality vectors for the documents and the queries.
In VSM, as mentioned above, the size of the document and the query vectors
is equal to the size of the vocabulary.  For large corpora, this size may
involve tens of thousands elements --- this can slow down the VSM modeling
and retrieval process.  So you are very likely to get faster performance
with retrieval based on LSA modeling, especially if you store the model
once constructed in a database file on the disk and carry out retrievals
using the disk-based model.


=head1 CAN THIS MODULE BE USED FOR GENERAL TEXT RETRIEVAL?

This module has only been tested for software retrieval.  For more general
text retrieval, you would need to replace the simple stemmer used in the
module by one based on, say, Porter's Stemming Algorithm.  You would also
need to vastly expand the list of stop words appropriate to the text
corpora of interest to you. As previously mentioned, the stop words are the
commonly occurring words that do not carry much discriminatory power from
the standpoint of distinguishing between the documents.  See the file
'stop_words.txt' in the 'examples' directory for how such a file must be
formatted.


=head1 HOW DOES ONE DEAL WITH VERY LARGE LIBRARIES/CORPORA?

It is not uncommon for large software libraries to consist of tens of
thousands of documents that include source-code files, documentation files,
README files, configuration files, etc.  The bug-localization work
presented recently by Shivani Rao and this author at the 2011 Mining
Software Repository conference (MSR11) was based on a relatively
small iBUGS dataset involving 6546 documents and a vocabulary size of
7553 unique words. (Here is a link to this work:
L<http://portal.acm.org/citation.cfm?id=1985451>.  Also note that the iBUGS
dataset was originally put together by V. Dallmeier and T. Zimmermann for
the evaluation of automated bug detection and localization tools.)  If C<V>
is the size of the vocabulary and C<M> the number of the documents in the
corpus, the size of each vector will be C<V> and size of the term-frequency
matrix for the entire corpus will be of size C<V>xC<M>.  So if you were to
duplicate the bug localization experiments in
L<http://portal.acm.org/citation.cfm?id=1985451> you would be dealing with
vectors of size 7553 and a term-frequency matrix of size 7553x6546.
Extrapolating these numbers to really large libraries/corpora, we are
obviously talking about very large matrices for SVD decomposition.  For
large libraries/corpora, it would be best to store away the model in a disk
file and to base all subsequent retrievals on the disk-stored models.  The
'examples' directory contains scripts that carry out retrievals on the
basis of disk-based models.  Further speedup in retrieval can be achieved
by using LSA to create reduced-dimensionality representations for the
documents and by basing retrievals on the stored versions of such
reduced-dimensionality representations.


=head1 ESTIMATING RETRIEVAL PERFORMANCE WITH PRECISION VS. RECALL CALCULATIONS

The performance of a retrieval algorithm is typically measured by two
properties, C<Precision> and C<Recall>, at a given rank C<r>.  As mentioned
in the L<http://portal.acm.org/citation.cfm?id=1985451> publication, at
given rank C<r>, Precision is the ratio of the number of retrieved
documents that are relevant to the total number of retrieved documents up
to that rank.  And, along the same lines, C<Recall> at a given rank C<r> is
the ratio of the number of retrieved documents that are relevant to the
total number of relevant documents.  The area under the
C<Precision>--C<Recall> curve is called the C<Average Precision> for a
query.  When the C<Average Precision> is averaged over all the queries, we
obtain what is known as C<Mean Average Precision> (MAP).  For an oracle,
the value of MAP should be 1.0.  On the other hand, for purely random
retrieval from a corpus, the value of MAP will be inversely proportional to
the size of the corpus.  (See the discussion in
L<http://RVL4.ecn.purdue.edu/~kak/SignifanceTesting.pdf> for further
explanation on these performance evaluators.)  This module includes methods
that allow you to carry out these performance measurements using the
relevancy judgments supplied through a disk file.  If human-supplied
relevancy judgments are not available, the module will be happy to estimate
relevancies for you just by determining the number of query words that
exist in a document.  Note, however, that relevancy judgments estimated in
this manner cannot be trusted. That is because ultimately it is the humans
who are the best judges of the relevancies of documents to queries.  The
humans bring to bear semantic considerations on the relevancy determination
problem that are beyond the scope of this module.


=head1 METHODS

The module provides the following methods for constructing VSM and LSA
models of a corpus, for using the models thus constructed for retrieval,
and for carrying out precision versus recall calculations for the
determination of retrieval accuracy on the corpora of interest to you.

=over

=item B<new():>

A call to C<new()> constructs a new instance of the C<Algorithm::VSM>
class:

    my $vsm = Algorithm::VSM->new( 
                     corpus_directory    => "",
                     corpus_vocab_db     => "corpus_vocab_db",
                     doc_vectors_db      => "doc_vectors_db",
                     lsa_doc_vectors_db  => "lsa_doc_vectors_db",  
                     stop_words_file     => "", 
                     want_stemming       => 1,
                     min_word_length     => 4,
                     lsa_svd_threshold   => 0.01, 
                     query_file          => "",  
                     relevancy_threshold => 5, 
                     relevancy_file      => $relevancy_file,
                     max_number_retrievals    => 10,
                     debug               => 0,
                                 );       

The values shown on the right side of the big arrows are the B<default
values for the parameters>.  The following nested list will now describe
each of the constructor parameters:

=over 16

=item I<corpus_directory:>

The parameter B<corpus_directory> points to the root of the
directory of documents for which you want to create a VSM or LSA model.

=item I<corpus_vocab_db:>

The parameter B<corpus_vocab_db> is for naming the DBM in which the corpus
vocabulary will be stored after it is subject to stemming and the
elimination of stop words.  Once a disk-based VSM model is created and
stored away in the file named by this parameter and the parameter to be
described next, it can subsequently be used directly for speedier
retrieval.


=item I<doc_vectors_db:>

The database named by B<doc_vectors_db> stores the document vector
representation for each document in the corpus.  Each document vector has
the same size as the corpus-wide vocabulary; each element of such a vector
is the number of occurrences of the word that corresponds to that position
in the vocabulary vector.  



=item I<lsa_doc_vectors_db>

The database named by B<lsa_doc_vectors_db> stores the
reduced-dimensionality vectors for each of the corpus documents.  These
vectors are creating for LSA modeling of a corpus.


=item I<stop_words_file>

The parameter B<stop_words_file> is for naming the file that contains the
stop words that you do not wish to include in the corpus vocabulary.  The
format of this file must be as shown in the sample file C<stop_words.txt>
in the 'examples' directory.  

=item I<want_stemming>

The boolean parameter B<want_stemming> determines whether or not the words
extracted from the documents would be subject to stemming.  As mentioned
elsewhere, stemming means that related words like 'programming' and
'programs' would both be reduced to the root word 'program'.


=item I<min_word_length> 

The parameter B<min_word_length> sets the minimum number
of characters in a word in order for it be included in the corpus
vocabulary.  

=item I<lsa_svd_threshold>

The parameter B<lsa_svd_threshold> is used for rejecting
singular values that are smaller than this threshold fraction of the
largest singular value.  This plays a critical role in creating
reduced-dimensionality document vectors in LSA modeling of a corpus.  

=item I<lsa_svd_threshold>

The parameter B<query_file> points to a file that contains the queries to
be used for calculating retrieval performance with C<Precision> and
C<Recall> numbers. The format of the query file must be as shown in the
sample file C<test_queries.txt> in the 'examples' directory.  

=item I<relevancy_threshold> 

The constructor parameter B<relevancy_threshold> is used for automatic
determination of document relevancies to queries on the basis of the number
of occurrences of query words in a document.  You can exercise control over
the process of determining relevancy of a document to a query by giving a
suitable value to the constructor parameter B<relevancy_threshold>.  A
document is considered relevant to a query only when the document contains
at least B<relevancy_threshold> number of query words.

=item I<max_number_retrievals>

The constructor parameter B<max_number_retrievals> stands for what it
means.  

=item I<debug>

Finally, when you set the boolean parameter C<debug>, the module outputs a
very large amount of intermediate results that are generated during model
construction and during matching a query with the document vectors.

=back

=begin html

<br>

=end html

=item B<get_corpus_vocabulary_and_word_counts():>

After you have constructed a new instance of the C<Algorithm::VSM> class,
you must now scan the corpus documents for constructing the corpus
vocabulary. This you do by:

    $vsm->get_corpus_vocabulary_and_word_counts();

The only time you do NOT need to call this method is when you are using a
previously constructed disk-stored VSM or LSA model for retrieval.


=item B<display_corpus_vocab():>

If you would like to see corpus vocabulary as constructed by the previous
call, make the call

    $vsm->display_corpus_vocab();

Note that this is a useful thing to do only on small test corpora. If you
must call this method on a large corpus, you might wish to direct the
output to a file.  The corpus vocabulary is shown automatically when
C<debug> option is turned on.


=item B<generate_document_vectors():>

This is a necessary step after the vocabulary used by a corpus is
constructed. (Of course, if you will be doing document retrieval through a
disk-stored VSM or LSA model, then you do not need to call this method.
You construct document vectors through the following call:

    $vsm->generate_document_vectors();


=item B<display_doc_vectors():>

If you would like to see the document vectors constructed by the previous
call, make the call:

    $vsm->display_doc_vectors();

Note that this is a useful thing to do only on small test corpora. If you
must call this method on a large corpus, you might wish to direct the
output to a file.  The document vectors are shown automatically when
C<debug> option is turned on.


=item B<retrieve_with_vsm():>

After you have constructed a VSM model, you call this method for document
retrieval for a given query C<@query>.  The call syntax is:

    my $retrievals = $vsm->retrieve_with_vsm( \@query );

The argument, C<@query>, is simply a list of words that you wish to use for
retrieval. The method returns a hash whose keys are the document names and
whose values the similarity distance between the document and the query.
As is commonly the case with VSM, this module uses the cosine similarity
distance when comparing a document vector with the query vector.


=item B<display_retrievals( $retrievals ):>

You can display the retrieved document names by calling this method using
the syntax:

    $vsm->display_retrievals( $retrievals );

where C<$retrievals> is a reference to the hash returned by a call to one
of the C<retrieve> methods.  The display method shown here respects the
retrieval size constraints expressed by the constructor parameter
C<max_number_retrievals>.


=item B<construct_lsa_model():>

If after you have extracted the corpus vocabulary and constructed document
vectors, you would do your retrieval with LSA modeling, you need to make
the following call:

    $vsm->construct_lsa_model();

The SVD decomposition that is carried out in LSA model construction uses
the constructor parameter C<lsa_svd_threshold> to decide how many of the
singular values to retain for the LSA model.  A singular is retained only
if it is larger than the C<lsa_svd_threshold> fraction of the largest
singular value.


=item B<retrieve_with_lsa():>

After you have built an LSA model through the call to
C<construct_lsa_model()>, you can retrieve the document names most 
similar to the query by:

    my $retrievals = $vsm->retrieve_with_lsa( \@query );

Subsequently, you can display the retrievals by calling the
C<display_retrievals($retrieval)> method described previously.

=item B<upload_vsm_model_from_disk():>

When you invoke the methods C<get_corpus_vocabulary_and_word_counts()> and
C<generate_document_vectors()>, that automatically deposits the VSM model
in the database files named with the constructor parameters
C<corpus_vocab_db> and C<doc_vectors_db>.  Subsequently, you can carry out
retrieval by directly using this disk-based VSM model for speedier
performance.  In order to do so, you must upload the disk-based model by

    $vsm->upload_vsm_model_from_disk();

Subsequently you call 

    my $retrievals = $vsm->retrieve_with_vsm( \@query );
    $vsm->display_retrievals( $retrievals );

for retrieval and for displaying the results.


=item B<upload_lsa_model_from_disk():>

When you invoke the methods C<get_corpus_vocabulary_and_word_counts()>,
C<generate_document_vectors()> and C<construct_lsa_model()>, that
automatically deposits the LSA model in the database files named with the
constructor parameters C<corpus_vocab_db>, C<doc_vectors_db> and
C<lsa_doc_vectors_db>.  Subsequently, you can carry out retrieval by
directly using this disk-based LSA model for speedier performance.  In
order to do so, you must upload the disk-based model by

    $vsm->upload_lsa_model_from_disk();

Subsequently you call 

    my $retrievals = $vsm->retrieve_with_lsa( \@query );
    $vsm->display_retrievals( $retrievals );

for retrieval and for displaying the results.


=item B<estimate_doc_relevancies($query_file):>

Before you can carry out precision and recall calculations to test the
accuracy of VSM and LSA based retrievals from a corpus, you need to have
available the relevancy judgments for the queries.  (A relevancy judgment
for a query is simply the list of documents relevant to that query.)
Relevancy judgments are commonly supplied by the humans who are familiar
with the corpus.  But if such human-supplied relevance judgments are not
available, you can invoke the following method to estimate them:

    $vsm->estimate_doc_relevancies("test_queries.txt");

For the above method call, a document is considered to be relevant to a
query if it contains several of the query words.  As to the minimum number
of query words that must exist in a document in order for the latter to be
considered relevant, that is determined by the C<relevancy_threshold>
parameter in the VSM constructor.

But note that this estimation of document relevancies to queries is NOT for
serious work.  The reason for that is because ultimately it is the humans
who are the best judges of the relevancies of documents to queries.  The
humans bring to bear semantic considerations on the relevancy determination
problem that are beyond the scope of this module.

The generated relevancies are deposited in a file named by the constructor
parameter C<relevancy_file>.

=item B<display_doc_relevancies():>

If you would like to see the document relevancies generated by the
previous method, you can call

    $vsm->display_doc_relevancies()


=item B<precision_and_recall_calculator():>

After you have created or obtained the relevancy judgments for your test
queries, you can make the following call to calculate C<Precision@rank> and
C<Recall@rank>:

    $vsm->precision_and_recall_calculator('vsm');

or 

    $vsm->precision_and_recall_calculator('lsa');

depending on whether you are testing VSM-based retrieval or LSA-based
retrieval.


=item B<display_precision_vs_recall_for_queries():>

A call to C<precision_and_recall_calculator()> will normally be followed
by the following call

    $vsm->display_precision_vs_recall_for_queries();

for displaying the C<Precision@rank> and C<Recall@rank> values.


=item B<display_map_values_for_queries():>

The area under the precision vs. recall curve for a given query is called
C<Average Precision> for that query.  When this area is averaged over all
the queries, you get C<MAP> (Mean Average Precision) as a measure of the
accuracy of the retrieval algorithm.  The C<Average Precision> values for
the queries and the overall C<MAP> can be printed out by calling

    $vsm->display_map_values_for_queries();


=item B<upload_document_relevancies_from_file():>

When human-supplied relevancies are available, you can upload them
into the program by calling

    $vsm->upload_document_relevancies_from_file();

These relevance judgments will be read from a file that is named with the
C<relevancy_file> constructor parameter.

=back


=head1 REQUIRED

This module requires the following modules:

    SDBM_File
    Storable
    PDL
    PDL::IO::Storable

The first two of these are needed for creating disk-based database records
for the VSM and LSA models.  The third is needed for calculating the SVD of
the term-frequency matrix. (PDL stands for Perl Data Language.)  The last
is needed for disk storage of the reduced-dimensionality vectors produced
during LSA calculations.

=head1 EXAMPLES

See the 'examples' directory in the distribution for the scripts listed
below:

=over

=item B<For Basic VSM-Based Retrieval:>

For basic VSM-based model construction and retrieval, run the script:

    retrieve_with_VSM.pl

=item B<For Basic LSA-Based Retrieval:>

For basic LSA-based model construction and retrieval, run the script:

    retrieve_with_LSA.pl

Both of the above scripts will store the corpus models created
in disk-based databases.

=item B<For VSM-Based Retrieval with a Disk-Stored Model:>

If you have previously run a script like C<retrieve_with_VSM.pl> and
no intervening code has modified the disk-stored VSM model of the corpus,
you can run the script

    retrieve_with_disk_based_VSM.pl

This would obviously work faster at retrieval since the VSM model would NOT
need to constructed for each new query.

=item B<For LSA-Based Retrieval with a Disk-Stored Model:>

If you have previously run a script like C<retrieve_with_LSA.pl> and
no intervening code has modified the disk-stored LSA model of the corpus,
you can run the script

    retrieve_with_disk_based_LSA.pl

The retrieval performance of such a script would be faster since the LSA
model would NOT need to constructed for each new query.

=item B<For Precision and Recall Calculations with VSM:>

To experiment with precision and recall calculations for VSM retrieval,
run the script:

    calculate_precision_and_recall_for_VSM.pl

Note that this script will carry out its own estimation of relevancy
judgments --- which in most cases would not be a safe thing to do.

=item B<For Precision and Recall Calculations with LSA:>

To experiment with precision and recall calculations for LSA retrieval,
run the script:

    calculate_precision_and_recall_for_LSA.pl

Note that this script will carry out its own estimation of relevancy
judgments --- which in most cases would not be a safe thing to do.


=item B<For Precision and Recall Calculations for VSM with
Human-Supplied Relevancies:>

Precision and recall calculations for retrieval accuracy determination are
best carried out with human-supplied judgments of relevancies of the
documents to queries.  If such judgments are available, run the
script:

    calculate_precision_and_recall_from_file_based_relevancies_for_VSM.pl

This script will print out the average precisions for the different test
queries and calculate the MAP metric of retrieval accuracy.

=item B<For Precision and Recall Calculations for LSA with
Human-Supplied Relevancies:>

If human-supplied relevancy judgments are available and you wish to
experiment with precision and recall calculations for LSA-based retrieval,
run the script:

    calculate_precision_and_recall_from_file_based_relevancies_for_LSA.pl

This script will print out the average precisions for the different test
queries and calculate the MAP metric of retrieval accuracy.

=back


=head1 EXPORT

None by design.

=head1 BUGS

Please notify the author if you encounter any bugs.  When sending email,
please place the string 'VSM' in the subject line to get past my spam
filter.

=head1 INSTALLATION

The usual

    perl Makefile.PL
    make
    make test
    make install

if you have root access.  If not, 

    perl Makefile.PL prefix=/some/other/directory/
    make
    make test
    make install

=head1 THANKS

Many thanks are owed to Shivani Rao for sharing with me her
deep insights in IR-based retrieval.  She was also of much
help with the debugging of this module by bringing to bear
on its output her amazing software forensic skills.

=head1 AUTHOR

Avinash Kak, kak@purdue.edu

If you send email, please place the string "VSM" in your
subject line to get past my spam filter.

=head1 COPYRIGHT

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

 Copyright 2011 Avinash Kak

=cut


