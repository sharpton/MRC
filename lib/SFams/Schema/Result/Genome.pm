use utf8;
package SFams::Schema::Result::Genome;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Genome

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<genomes>

=cut

__PACKAGE__->table("genomes");

=head1 ACCESSORS

=head2 taxon_oid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 ncbi_taxon_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 ncbi_project_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 completion

  data_type: 'enum'
  extra: {list => ["Draft","Finished","Permanent Draft"]}
  is_nullable: 0

=head2 domain

  data_type: 'enum'
  extra: {list => ["Bacteria","Archaea","Eukaryota"]}
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 directory

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 phylum

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 class

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 order

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=head2 family

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 genus

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 sequencing_center

  data_type: 'text'
  is_nullable: 0

=head2 gene_count

  data_type: 'integer'
  is_nullable: 0

=head2 genome_size

  data_type: 'integer'
  is_nullable: 0

=head2 scaffold_count

  data_type: 'integer'
  is_nullable: 0

=head2 img_release

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 add_date

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 is_public

  data_type: 'enum'
  extra: {list => ["Yes","No"]}
  is_nullable: 0

=head2 gc

  data_type: 'decimal'
  is_nullable: 1
  size: [3,1]

=head2 gram_stain

  data_type: 'enum'
  extra: {list => ["+","-"]}
  is_nullable: 1

=head2 shape

  data_type: 'text'
  is_nullable: 1

=head2 arrangement

  data_type: 'text'
  is_nullable: 1

=head2 endospores

  data_type: 'text'
  is_nullable: 1

=head2 motility

  data_type: 'text'
  is_nullable: 1

=head2 salinity

  data_type: 'text'
  is_nullable: 1

=head2 oxygen_req

  data_type: 'text'
  is_nullable: 1

=head2 habitat

  data_type: 'text'
  is_nullable: 1

=head2 temp_range

  data_type: 'text'
  is_nullable: 1

=head2 pathogenic_in

  data_type: 'text'
  is_nullable: 1

=head2 disease

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "taxon_oid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "ncbi_taxon_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "ncbi_project_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "completion",
  {
    data_type => "enum",
    extra => { list => ["Draft", "Finished", "Permanent Draft"] },
    is_nullable => 0,
  },
  "domain",
  {
    data_type => "enum",
    extra => { list => ["Bacteria", "Archaea", "Eukaryota"] },
    is_nullable => 0,
  },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 256 },
  "directory",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "phylum",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "class",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "order",
  { data_type => "varchar", is_nullable => 0, size => 30 },
  "family",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "genus",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "sequencing_center",
  { data_type => "text", is_nullable => 0 },
  "gene_count",
  { data_type => "integer", is_nullable => 0 },
  "genome_size",
  { data_type => "integer", is_nullable => 0 },
  "scaffold_count",
  { data_type => "integer", is_nullable => 0 },
  "img_release",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "add_date",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "is_public",
  {
    data_type => "enum",
    extra => { list => ["Yes", "No"] },
    is_nullable => 0,
  },
  "gc",
  { data_type => "decimal", is_nullable => 1, size => [3, 1] },
  "gram_stain",
  { data_type => "enum", extra => { list => ["+", "-"] }, is_nullable => 1 },
  "shape",
  { data_type => "text", is_nullable => 1 },
  "arrangement",
  { data_type => "text", is_nullable => 1 },
  "endospores",
  { data_type => "text", is_nullable => 1 },
  "motility",
  { data_type => "text", is_nullable => 1 },
  "salinity",
  { data_type => "text", is_nullable => 1 },
  "oxygen_req",
  { data_type => "text", is_nullable => 1 },
  "habitat",
  { data_type => "text", is_nullable => 1 },
  "temp_range",
  { data_type => "text", is_nullable => 1 },
  "pathogenic_in",
  { data_type => "text", is_nullable => 1 },
  "disease",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</taxon_oid>

=back

=cut

__PACKAGE__->set_primary_key("taxon_oid");

=head1 RELATIONS

=head2 genes

Type: has_many

Related object: L<SFams::Schema::Result::Gene>

=cut

__PACKAGE__->has_many(
  "genes",
  "SFams::Schema::Result::Gene",
  { "foreign.taxon_oid" => "self.taxon_oid" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KFoRNoGQIiV7yeaFiMFFjw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
