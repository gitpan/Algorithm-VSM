use ExtUtils::MakeMaker;
use File::Copy;

if ($^V lt v5.10) {
   die("Algorithm::VSM has only been tested on Perl 5.10.0.\n" .
   "Your perl version is $].\n");
}

copy("perl/MANIFEST.perl","MANIFEST");

WriteMakefile(
    NAME         => 'Algorithm::VSM',
    VERSION_FROM => 'lib/Algorithm/VSM.pm',
    PREREQ_PM    => { Storable => '2.20',
                      SDBM_File => '1.06',
                      PDL => '2.4.9',
                      PDL::IO::Storable,
                    },
    AUTHOR       => 'Avinash Kak (kak@purdue.edu)',
    ABSTRACT     => 'A pure-Perl implementation of VSM and LSA algorithms for retrieval from software libraries',
    clean        => {FILES => join(" ",
                                   map { "$_ */$_ */*/$_" }
                                   qw( *% *.b[ac]k *.old *.orig ) )
                    },
);

