use utf8;
package SFams::Schema::Result::Gene;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Gene

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<genes>

=cut

__PACKAGE__->table("genes");

=head1 ACCESSORS

=head2 gene_oid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 taxon_oid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 protein_id

  data_type: 'varchar'
  is_nullable: 1
  size: 15

=head2 type

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=head2 start

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 end

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 strand

  data_type: 'enum'
  extra: {list => [-1,0,1]}
  is_nullable: 0

=head2 locus

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 100

=head2 description

  data_type: 'varchar'
  is_nullable: 0
  size: 1000

=head2 dna

  data_type: 'text'
  is_nullable: 0

=head2 protein

  data_type: 'text'
  is_nullable: 1

=head2 scaffold_name

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 scaffold_id

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=cut

__PACKAGE__->add_columns(
  "gene_oid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "taxon_oid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "protein_id",
  { data_type => "varchar", is_nullable => 1, size => 15 },
  "type",
  { data_type => "varchar", is_nullable => 0, size => 64 },
  "start",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "end",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "strand",
  { data_type => "enum", extra => { list => [-1, 0, 1] }, is_nullable => 0 },
  "locus",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "description",
  { data_type => "varchar", is_nullable => 0, size => 1000 },
  "dna",
  { data_type => "text", is_nullable => 0 },
  "protein",
  { data_type => "text", is_nullable => 1 },
  "scaffold_name",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "scaffold_id",
  { data_type => "varchar", is_nullable => 0, size => 15 },
);

=head1 PRIMARY KEY

=over 4

=item * L</gene_oid>

=back

=cut

__PACKAGE__->set_primary_key("gene_oid");

=head1 RELATIONS

=head2 familymembers

Type: has_many

Related object: L<SFams::Schema::Result::Familymember>

=cut

__PACKAGE__->has_many(
  "familymembers",
  "SFams::Schema::Result::Familymember",
  { "foreign.gene_oid" => "self.gene_oid" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 taxon_oid

Type: belongs_to

Related object: L<SFams::Schema::Result::Genome>

=cut

__PACKAGE__->belongs_to(
  "taxon_oid",
  "SFams::Schema::Result::Genome",
  { taxon_oid => "taxon_oid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);

=head2 unknowngene

Type: might_have

Related object: L<SFams::Schema::Result::Unknowngene>

=cut

__PACKAGE__->might_have(
  "unknowngene",
  "SFams::Schema::Result::Unknowngene",
  { "foreign.gene_oid" => "self.gene_oid" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:c341la4csixSA3aD21SJnw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
