#!/usr/bin/perl

use strict;
use File::Basename;
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';

my @dir=("/");
@dir=@ARGV if @ARGV;
my %data=();

Gtk2::main(&createwidgets());

0;

sub loaddata {
	my $tm=shift;
	foreach my $file (keys %data){ $data{$file}->{"del"}=1; }
	foreach my $dir (@dir){ &readdir($dir); }
	foreach my $dir (@dir){ &adddir($dir,0,$tm,undef); }
}

sub readdir {
	my $dir=shift;
	open DU,"du -a \"$dir\" |";
	while(<DU>){
		chomp $_;
		(my $si,my $file)=split /\t+/,$_,2;
		my $dir=dirname($file);
		$data{$file}->{"size"}=$si;
		$data{$dir}->{"sub"}->{$file}=1;
		delete $data{$file}->{"del"};
	}
	close DU;
}

sub adddir {
	(my $dir,my $dirsize,my $tm,my $parent)=@_;
	if($data{$dir}->{"del"}){
		&deldir($dir,$tm);
		return 0;
	}
	$data{$dir}->{"it"}=$tm->append($parent) if !exists $data{$dir}->{"it"};
	my $it=$data{$dir}->{"it"};
	my $si=$data{$dir}->{"size"};
	$dirsize=$si if !$dirsize;
	$dirsize=1 if !$dirsize;
	$tm->set($it,0=>basename($dir),1=>$si,2=>&humansize($si),3=>$si/$dirsize*100);
	foreach my $file (keys %{$data{$dir}->{"sub"}}){ &adddir($file,$si,$tm,$it); }
}

sub deldir {
	(my $dir,my $tm)=@_;
	foreach my $file (keys %{$data{$dir}->{"sub"}}){ &deldir($file,$tm); }
	$tm->remove($data{$dir}->{"it"}) if exists $data{$dir}->{"it"};
	delete $data{$dir};
}

sub humansize {
	my $size=shift;
	my @ext=("k","M","G","T");
	while($size>=1000 && @ext>1){ $size/=1024; shift @ext; }
	my $num=$size<10 ? 1 : 0;
	return sprintf "%.".$num."f%s",$size,$ext[0];
}

sub createwidgets {
	# TreeStore
	my $tm=Gtk2::TreeStore->new("Glib::String","Glib::Int","Glib::String","Glib::Int");
	$tm->set_sort_column_id(1,"descending");
	# CellRenderer
	my $trs=Gtk2::CellRendererText->new;
	my $trp=Gtk2::CellRendererProgress->new;
	my $trf=Gtk2::CellRendererText->new;
	# TreeViewColumn
	my $tc=Gtk2::TreeViewColumn->new();
	$tc->pack_start($trs,FALSE);
	$tc->add_attribute($trs,text=>2);
	$tc->pack_start($trp,FALSE);
	$tc->add_attribute($trp,value=>3);
	$tc->pack_start($trf,FALSE);
	$tc->add_attribute($trf,text=>0);
	# TreeView
	my $tv=Gtk2::TreeView->new($tm);
	$tv->append_column($tc);
	# ScrolledWindow
	my $sc=Gtk2::ScrolledWindow->new();
	$sc->add_with_viewport($tv);
	# ButtonBox
	my $br=Gtk2::Button->new_from_stock("gtk-refresh");
	$br->signal_connect('clicked'=>sub{ &loaddata($tm); });
	my $bc=Gtk2::Button->new_from_stock("gtk-close");
	$bc->signal_connect('clicked'=>sub{ Gtk2->main_quit; });
	my $bb=Gtk2::HButtonBox->new();
	$bb->add($br);
	$bb->add($bc);
	# VBox
	my $vb=Gtk2::VBox->new(FALSE,0);
	$vb->pack_start($sc,TRUE,TRUE,0);
	$vb->pack_start($bb,FALSE,FALSE,0);
	# Window
	my $wnd = Gtk2::Window->new('toplevel');
	$wnd->signal_connect(destroy=>sub{ Gtk2->main_quit; });
	$wnd->add($vb);
	$wnd->set_default_size(500,700);
	$wnd->show_all();
	&loaddata($tm);
	return $wnd;
}
