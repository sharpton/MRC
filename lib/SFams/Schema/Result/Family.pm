use utf8;
package SFams::Schema::Result::Family;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Family

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<family>

=cut

__PACKAGE__->table("family");

=head1 ACCESSORS

=head2 famid

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 familyconstruction_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

foreign key to familyconstruction

=head2 fam_alt_id

  data_type: 'varchar'
  is_nullable: 1
  size: 256

This can/shoud be user as a secondary identifier for families. (e.g Pfam families could have "PF0001". 

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 description

  data_type: 'varchar'
  is_nullable: 1
  size: 512

=head2 alnpath

  data_type: 'text'
  is_nullable: 1

Gives path to the file containing the alignment of all family members

=head2 seed_alnpath

  data_type: 'text'
  is_nullable: 1

=head2 hmmpath

  data_type: 'text'
  is_nullable: 1

=head2 reftree

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 alltree

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 size

  data_type: 'integer'
  is_nullable: 1

Number of sequences used to construct the family

=head2 universality

  data_type: 'integer'
  is_nullable: 1

=head2 evenness

  data_type: 'integer'
  is_nullable: 1

=head2 arch_univ

  data_type: 'integer'
  is_nullable: 1

=head2 bact_univ

  data_type: 'integer'
  is_nullable: 1

=head2 euk_univ

  data_type: 'integer'
  is_nullable: 1

=head2 unknown_genes

  data_type: 'integer'
  is_nullable: 1

=head2 pathogen_percent

  data_type: 'decimal'
  is_nullable: 1
  size: [4,1]

=head2 aquatic_percent

  data_type: 'decimal'
  is_nullable: 1
  size: [4,1]

=cut

__PACKAGE__->add_columns(
  "famid",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "familyconstruction_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "fam_alt_id",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "description",
  { data_type => "varchar", is_nullable => 1, size => 512 },
  "alnpath",
  { data_type => "text", is_nullable => 1 },
  "seed_alnpath",
  { data_type => "text", is_nullable => 1 },
  "hmmpath",
  { data_type => "text", is_nullable => 1 },
  "reftree",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "alltree",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "size",
  { data_type => "integer", is_nullable => 1 },
  "universality",
  { data_type => "integer", is_nullable => 1 },
  "evenness",
  { data_type => "integer", is_nullable => 1 },
  "arch_univ",
  { data_type => "integer", is_nullable => 1 },
  "bact_univ",
  { data_type => "integer", is_nullable => 1 },
  "euk_univ",
  { data_type => "integer", is_nullable => 1 },
  "unknown_genes",
  { data_type => "integer", is_nullable => 1 },
  "pathogen_percent",
  { data_type => "decimal", is_nullable => 1, size => [4, 1] },
  "aquatic_percent",
  { data_type => "decimal", is_nullable => 1, size => [4, 1] },
);

=head1 PRIMARY KEY

=over 4

=item * L</famid>

=back

=cut

__PACKAGE__->set_primary_key("famid");

=head1 UNIQUE CONSTRAINTS

=head2 C<fam_alt_id>

=over 4

=item * L</fam_alt_id>

=back

=cut

__PACKAGE__->add_unique_constraint("fam_alt_id", ["fam_alt_id"]);

=head1 RELATIONS

=head2 alltree

Type: belongs_to

Related object: L<SFams::Schema::Result::Tree>

=cut

__PACKAGE__->belongs_to(
  "alltree",
  "SFams::Schema::Result::Tree",
  { treeid => "alltree" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);

=head2 analyses

Type: has_many

Related object: L<SFams::Schema::Result::Analysis>

=cut

__PACKAGE__->has_many(
  "analyses",
  "SFams::Schema::Result::Analysis",
  { "foreign.famid" => "self.famid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 familyconstruction

Type: belongs_to

Related object: L<SFams::Schema::Result::Familyconstruction>

=cut

__PACKAGE__->belongs_to(
  "familyconstruction",
  "SFams::Schema::Result::Familyconstruction",
  { familyconstruction_id => "familyconstruction_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 familymembers

Type: has_many

Related object: L<SFams::Schema::Result::Familymember>

=cut

__PACKAGE__->has_many(
  "familymembers",
  "SFams::Schema::Result::Familymember",
  { "foreign.famid" => "self.famid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 reftree

Type: belongs_to

Related object: L<SFams::Schema::Result::Tree>

=cut

__PACKAGE__->belongs_to(
  "reftree",
  "SFams::Schema::Result::Tree",
  { treeid => "reftree" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);

=head2 searchresults

Type: has_many

Related object: L<SFams::Schema::Result::Searchresult>

=cut

__PACKAGE__->has_many(
  "searchresults",
  "SFams::Schema::Result::Searchresult",
  { "foreign.famid" => "self.famid" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ardm+5tKmEdtTZ0ghk9LBw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
