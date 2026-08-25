#!/bin/sh
#
# $FML: sgml_compile.sh,v 1.1 2005/06/25 10:03:38 fukachan Exp $
#

#
# initialize variables
#
mode=html

fml_dir=`dirname $0`/../..
gnu_dir=`dirname $0`/../../../gnu
cur_dir=`pwd`
out_dir=$cur_dir/book
out_html=$cur_dir/book.html
out_txt=$cur_dir/book.txt
out_rtf=$cur_dir/book.rtf
tmp_dir=/var/tmp
tmp_file=$tmp_dir/tmpfile.$$

fml_sgml_dir=$fml_dir/doc/share/sgml
fml_catalog_path=$fml_sgml_dir/catalog
sgmltoolslite_catalog_path=$gnu_dir/dist/sgmltools-lite/dsssl/sgmltools.cat
# XXX The catalog used to be looked for at /usr/pkg/etc/sgml/catalog
# XXX alone, which is pkgsrc's prefix.  On anything else -- a Debian
# XXX box, a Mac, a Linux container -- there is nothing there, so the
# XXX catalog list silently contained one path that does not exist.
pkg_catalog=""
for d in /usr/pkg/etc/sgml /usr/local/etc/sgml /etc/sgml /opt/local/etc/sgml
do
   if [ -f $d/catalog ]; then
	pkg_catalog=$d/catalog
	break
   fi
done

sgml_catalog_files=$SGML_CATALOG_FILES:$pkg_catalog:$sgmltoolslite_catalog_path
sgml_search_path=$SGML_SEARCH_PATH:$fml_catalog_path:$cur_dir;

# XXX This used to test $openjade and friends by absolute
# XXX path, so the documentation could only be built on a machine with
# XXX pkgsrc.  Everywhere else it said
# XXX
# XXX     error: $openjade not found
# XXX
# XXX which reads as "openjade is missing" even when it is installed,
# XXX somewhere else.  Ask PATH, and say what to install when the
# XXX answer is no.
missing=""
for cmd in openjade lynx w3m
do
   eval "path_$cmd=\"\""
   for dir in `echo $PATH | tr ':' ' '`
   do
	if [ -x $dir/$cmd ]; then
	   eval "path_$cmd=$dir/$cmd"
	   break
	fi
   done

   eval "found=\$path_$cmd"
   if [ X"$found" = X ]; then
	missing="$missing $cmd"
   fi
done

if [ X"$missing" != X ]; then
   echo "error: not in PATH:$missing"
   echo ""
   echo "the documentation is built with openjade (an SGML/DSSSL"
   echo "processor) and rendered to text with lynx or w3m."
   echo ""
   echo "    pkgsrc        pkg_add openjade lynx w3m"
   echo "    Debian        apt install openjade lynx w3m"
   echo "    Homebrew      brew install openjade lynx w3m"
   echo ""
   exit 1
fi

openjade=$path_openjade
lynx=$path_lynx
w3m=$path_w3m

#
# getopts
#
set -- `getopt dm: $*`

if test $? != 0; then echo 'Usage: ...'; exit 2; fi

for i
do
        case $i
        in
        -d)
                debug=1;
                shift;;
        -m)
		mode=$2; shift;
                shift;;
        --)
                shift; break;;
        esac
done

source=$cur_dir/$1


#
# fix environment
#
TMPDIR=$tmp_dir ; export TMPDIR
COLS=72         ; export COLS
SGML_SEARCH_PATH=$sgml_search_path    ; export SGML_SEARCH_PATH
SGML_CATALOG_FILES=$sgml_catalog_files; export SGML_CATALOG_FILES

#
# main: go!
# 
common_options="\
		-v  \
		-o $tmp_file \
		-c $fml_catalog_path "

if [ "X$mode" = "Xhtml" -o "X$mode" = "Xonehtml" ];then
   test -d $out_dir || mkdir $out_dir
   chdir $out_dir   || exit 1

   dsssl=$gnu_dir/dist/sgmltools-lite/dsssl/html.dsl

   $openjade $common_options \
	-t sgml \
	-c $fml_catalog_path  \
	-d $dsssl#$mode \
	-d ${FML_DSL:-$fml_sgml_dir/fml.dsl} \
	> $out_html < $source

elif [ "X$mode" = "Xlynx" ];then

   dsssl=$gnu_dir/dist/sgmltools-lite/dsssl/ascii-lynx.dsl

   $openjade $common_options \
	-t sgml \
	-d $dsssl#html  \
	> $out_html < $source

   $lynx -dump -nolist -force_html $out_html > $out_txt
   mv $out_html $tmp_dir

elif [ "X$mode" = "Xw3m" ];then

   dsssl=$gnu_dir/dist/sgmltools-lite/dsssl/ascii-w3m.dsl

   $openjade $common_options \
	-t sgml \
	-d $dsssl#html  \
	> $out_html < $source

   $w3m -T text/html -dump $out_html > $out_txt
   mv $out_html $tmp_dir

else
   echo "error: unknown mode: $mode"	
fi

exit 0;
