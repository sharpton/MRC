use utf8;
package SFams::Schema::Result::Unknowngene;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Unknowngene - Contains a  list of genes with unknown function

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<unknowngenes>

=cut

__PACKAGE__->table("unknowngenes");

=head1 ACCESSORS

=head2 gene_oid

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 pfam

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 product

  data_type: 'enum'
  extra: {list => ["Yes","No"]}
  is_nullable: 1

=head2 name

  data_type: 'enum'
  extra: {list => ["Yes","No"]}
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "gene_oid",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "pfam",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "product",
  {
    data_type => "enum",
    extra => { list => ["Yes", "No"] },
    is_nullable => 1,
  },
  "name",
  {
    data_type => "enum",
    extra => { list => ["Yes", "No"] },
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</gene_oid>

=back

=cut

__PACKAGE__->set_primary_key("gene_oid");

=head1 RELATIONS

=head2 gene_oid

Type: belongs_to

Related object: L<SFams::Schema::Result::Gene>

=cut

__PACKAGE__->belongs_to(
  "gene_oid",
  "SFams::Schema::Result::Gene",
  { gene_oid => "gene_oid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/gfyDQF7EK7/8KJdr6EDqA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
