package IMG::Schema::Result::Family;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

IMG::Schema::Result::Family

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

=head2 fam_alt_id

  data_type: 'varchar'
  is_nullable: 1
  size: 256

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
__PACKAGE__->set_primary_key("famid");
__PACKAGE__->add_unique_constraint("fam_alt_id", ["fam_alt_id"]);

=head1 RELATIONS

=head2 analyses

Type: has_many

Related object: L<IMG::Schema::Result::Analysis>

=cut

__PACKAGE__->has_many(
  "analyses",
  "IMG::Schema::Result::Analysis",
  { "foreign.famid" => "self.famid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 reftree

Type: belongs_to

Related object: L<IMG::Schema::Result::Tree>

=cut

__PACKAGE__->belongs_to(
  "reftree",
  "IMG::Schema::Result::Tree",
  { treeid => "reftree" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 alltree

Type: belongs_to

Related object: L<IMG::Schema::Result::Tree>

=cut

__PACKAGE__->belongs_to(
  "alltree",
  "IMG::Schema::Result::Tree",
  { treeid => "alltree" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 familyconstruction

Type: belongs_to

Related object: L<IMG::Schema::Result::Familyconstruction>

=cut

__PACKAGE__->belongs_to(
  "familyconstruction",
  "IMG::Schema::Result::Familyconstruction",
  { familyconstruction_id => "familyconstruction_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 familymembers

Type: has_many

Related object: L<IMG::Schema::Result::Familymember>

=cut

__PACKAGE__->has_many(
  "familymembers",
  "IMG::Schema::Result::Familymember",
  { "foreign.famid" => "self.famid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 searchresults

Type: has_many

Related object: L<IMG::Schema::Result::Searchresult>

=cut

__PACKAGE__->has_many(
  "searchresults",
  "IMG::Schema::Result::Searchresult",
  { "foreign.famid" => "self.famid" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-03-14 16:34:50
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EvQRuyxxkAW5+n+LfCUlJQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
