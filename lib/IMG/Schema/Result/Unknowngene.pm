package IMG::Schema::Result::Unknowngene;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

IMG::Schema::Result::Unknowngene

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
__PACKAGE__->set_primary_key("gene_oid");

=head1 RELATIONS

=head2 gene_oid

Type: belongs_to

Related object: L<IMG::Schema::Result::Gene>

=cut

__PACKAGE__->belongs_to(
  "gene_oid",
  "IMG::Schema::Result::Gene",
  { gene_oid => "gene_oid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-03-14 16:34:50
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:5uBPSeyQr8EXlEavwKyPWw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
