use utf8;
package SFams::Schema::Result::Familymember;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Familymember

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<familymembers>

=cut

__PACKAGE__->table("familymembers");

=head1 ACCESSORS

=head2 familymember_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 famid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

Foreign key to "family" table

=head2 gene_oid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

foreign key to "genes" table

=head2 orf_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

foreign key to "orfs" table

=head2 classification_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

foreign key to classification_parameters table

=cut

__PACKAGE__->add_columns(
  "familymember_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "famid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "gene_oid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "orf_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "classification_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</familymember_id>

=back

=cut

__PACKAGE__->set_primary_key("familymember_id");

=head1 RELATIONS

=head2 classification

Type: belongs_to

Related object: L<SFams::Schema::Result::ClassificationParameter>

=cut

__PACKAGE__->belongs_to(
  "classification",
  "SFams::Schema::Result::ClassificationParameter",
  { classification_id => "classification_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 famid

Type: belongs_to

Related object: L<SFams::Schema::Result::Family>

=cut

__PACKAGE__->belongs_to(
  "famid",
  "SFams::Schema::Result::Family",
  { famid => "famid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 gene_oid

Type: belongs_to

Related object: L<SFams::Schema::Result::Gene>

=cut

__PACKAGE__->belongs_to(
  "gene_oid",
  "SFams::Schema::Result::Gene",
  { gene_oid => "gene_oid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 orf

Type: belongs_to

Related object: L<SFams::Schema::Result::Orf>

=cut

__PACKAGE__->belongs_to(
  "orf",
  "SFams::Schema::Result::Orf",
  { orf_id => "orf_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:OT5NP4IOmB4AG1ojoLO8Mg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
