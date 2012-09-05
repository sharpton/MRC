package Sfams::Schema::Result::Searchresult;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Searchresult

=cut

__PACKAGE__->table("searchresults");

=head1 ACCESSORS

=head2 searchresults_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 orf_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 famid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 evalue

  data_type: 'double precision'
  is_nullable: 1

=head2 score

  data_type: 'float'
  is_nullable: 1

=head2 other_searchstats

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "searchresults_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "orf_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "famid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "evalue",
  { data_type => "double precision", is_nullable => 1 },
  "score",
  { data_type => "float", is_nullable => 1 },
  "other_searchstats",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("searchresults_id");
__PACKAGE__->add_unique_constraint("orf_id_famid", ["orf_id", "famid"]);

=head1 RELATIONS

=head2 famid

Type: belongs_to

Related object: L<Sfams::Schema::Result::Family>

=cut

__PACKAGE__->belongs_to(
  "famid",
  "Sfams::Schema::Result::Family",
  { famid => "famid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 orf

Type: belongs_to

Related object: L<Sfams::Schema::Result::Orf>

=cut

__PACKAGE__->belongs_to(
  "orf",
  "Sfams::Schema::Result::Orf",
  { orf_id => "orf_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Q7+6WdqXPrmXFe8i2C7+2A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
