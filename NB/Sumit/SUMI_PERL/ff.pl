#!/usr/bin/perl

my $x = 17150;
$x =~ s/0+$//;
my $a = qx(ls /var/lib/asterisk/static-http/config/Recordings/10-05-2024/16/$x*);
print $a;
if($a){
@aa = split /\n/,$a;

$l = scalar @aa;
for(my $i = 0; $i< scalar @aa; $i++){
	my $p = "$aa[$i]";
	@m = split /\/var\/lib\/asterisk\/static-http\/config\/Recordings\/10-05-2024\/16\//,$p;
	print "@m\n";
	@ss = split /-/, $m[1];
	print "=$ss[0]=\n";

}
print $l;
}
