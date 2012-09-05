package Sfams::Schema::Result::Familymember;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Familymember

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

=head2 gene_oid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 orf_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 classification_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

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
__PACKAGE__->set_primary_key("familymember_id");

=head1 RELATIONS

=head2 classification

Type: belongs_to

Related object: L<Sfams::Schema::Result::ClassificationParameter>

=cut

__PACKAGE__->belongs_to(
  "classification",
  "Sfams::Schema::Result::ClassificationParameter",
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

Related object: L<Sfams::Schema::Result::Family>

=cut

__PACKAGE__->belongs_to(
  "famid",
  "Sfams::Schema::Result::Family",
  { famid => "famid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 gene_oid

Type: belongs_to

Related object: L<Sfams::Schema::Result::Gene>

=cut

__PACKAGE__->belongs_to(
  "gene_oid",
  "Sfams::Schema::Result::Gene",
  { gene_oid => "gene_oid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);

=head2 orf

Type: belongs_to

Related object: L<Sfams::Schema::Result::Orf>

=cut

__PACKAGE__->belongs_to(
  "orf",
  "Sfams::Schema::Result::Orf",
  { orf_id => "orf_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:qCucZ90JXxPhNWE/MZPrKg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
