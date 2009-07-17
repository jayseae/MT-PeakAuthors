# ===========================================================================
# A Movable Type plugin to select entries by authors over recent days.
# Copyright 2006 Everitz Consulting <everitz.com>.
#
# This program is free software:  You may redistribute it and/or modify it
# it under the terms of the Artistic License version 2 as published by the
# Open Source Initiative.
#
# This program is distributed in the hope that it will be useful but does
# NOT INCLUDE ANY WARRANTY; Without even the implied warranty of FITNESS
# FOR A PARTICULAR PURPOSE.
#
# You should have received a copy of the Artistic License with this program.
# If not, see <http://www.opensource.org/licenses/artistic-license-2.0.php>.
# ===========================================================================
package MT::Plugin::PeakAuthors;

use base qw(MT::Plugin);
use strict;

use MT;
use MT::Util qw(offset_time_list);

# version
use vars qw($VERSION);
$VERSION = '1.0.1';

my $about = {
  name => 'MT-PeakAuthors',
  description => 'Select entries by authors over recent days.',
  author_name => 'Everitz Consulting',
  author_link => 'http://everitz.com/',
  version => $VERSION,
};
MT->add_plugin(new MT::Plugin($about));

use MT::Template::Context;
MT::Template::Context->add_container_tag(PeakAuthors => \&PeakAuthors);

MT::Template::Context->add_tag(PeakAuthorName => \&ReturnValue);
MT::Template::Context->add_tag(PeakAuthorDisplayName => \&ReturnValue);
MT::Template::Context->add_tag(PeakAuthorEmail => \&ReturnValue);
MT::Template::Context->add_tag(PeakAuthorEntryCount => \&ReturnValue);
MT::Template::Context->add_tag(PeakAuthorURL => \&ReturnValue);

sub PeakAuthors {
  my($ctx, $args, $cond) = @_;

  # limit entries
  my $lastn = $args->{lastn} || 0;

  # set time frame
  my $days = $args->{days} || 7;
  return $ctx->error(MT->translate(
    "Invalid data: [_1] must be numeric!", qq(<MTPeakAuthors days="$days">))
  ) unless ($days =~ /^\d*$/);
  my @ago = offset_time_list(time - 60 * 60 * 24 * $days);
  my $ago = sprintf "%04d%02d%02d%02d%02d%02d", $ago[5]+1900, $ago[4]+1, @ago[3,2,1,0];
  my @now = offset_time_list(time);
  my $now = sprintf "%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, @now[3,2,1,0];

  # load entries
  use MT::Entry;
  my @site_entries = MT::Entry->load({
    status => MT::Entry::RELEASE(),
    created_on =>  [ $ago, $now ]
  }, {
    range => { created_on => 1 }
  });

  # filtered entry list (blog)
  my @blog_entries;
  if ($args->{blog}) {
    my %blog = map { $_ => 1 } split(/\sOR\s/, $args->{blog});
    @blog_entries = grep { exists $blog{$_->blog_id} } @site_entries;
  } else {
    @blog_entries = @site_entries;
  }

  # filtered entry list (category)
  my @cat_entries;
  if ($args->{category}) {
    my $app = MT->instance;
    my $category = $args->{category};
    my $negative = ($category =~ s/^NOT\s//) ? 1 : 0;
    use MT::Category;
    my %category =
      map { $_->id => 1 }
      map { MT::Category->load({ label => $_ }) } 
      split(/\sOR\s/, $category);
    foreach (@blog_entries) {
      my $cats;
      my @cat_ids;
      if ($args->{primary}) {
        if (my $cat_pri = $_->category) {
          push @cat_entries, $_ if (exists $category{$cat_pri->id});
        }
      } else {
        $cats = $_->categories;
        @cat_ids = map { $_->id } @$cats;
        my @cats;
        if ($negative) {
          @cats = grep { !exists $category{$_} } @cat_ids;
          next unless (@cats == @cat_ids);
        } else {
          @cats = grep { exists $category{$_} } @cat_ids;
        }
        push @cat_entries, $_ if (scalar @cats);
      }
    }
  } else {
    @cat_entries = @blog_entries;
  }
  @cat_entries = sort { $b->created_on cmp $a->created_on } @cat_entries;

  my @order;
  my %author;
  foreach (@cat_entries) {
    my $author_id = $_->author_id;
    push @order, $author_id unless ($author{$author_id});
    $author{$author_id}++;
  }

  my $builder = $ctx->stash('builder');
  my $tokens = $ctx->stash('tokens');
  my $res = '';

  my $done = 0;
  foreach (@order) {
    last if ($lastn && $done >= $lastn);
    my $author = MT::Author->load($_);
    next unless ($author);
    $ctx->{__stash}{PeakAuthorName} = $author->name;
    $ctx->{__stash}{PeakAuthorDisplayName} = $author->nickname;
    $ctx->{__stash}{PeakAuthorEmail} = $author->email;
    $ctx->{__stash}{PeakAuthorEntryCount} = $author{$_};
    $ctx->{__stash}{PeakAuthorURL} = $author->url;
    my $out = $builder->build($ctx, $tokens);
    return $ctx->error($builder->errstr) unless defined $out;
    $res .= $out;
    $done++;
  }
  $res;
}

sub ReturnValue {
  my ($ctx, $args) = @_;
  my $val = $ctx->stash($ctx->stash('tag'));
  $val;
}

1;
