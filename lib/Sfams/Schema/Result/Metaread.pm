package Sfams::Schema::Result::Metaread;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Metaread

=cut

__PACKAGE__->table("metareads");

=head1 ACCESSORS

=head2 read_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 sample_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 read_alt_id

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=cut

__PACKAGE__->add_columns(
  "read_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "sample_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "read_alt_id",
  { data_type => "varchar", is_nullable => 0, size => 256 },
);
__PACKAGE__->set_primary_key("read_id");
__PACKAGE__->add_unique_constraint("sample_id_read_alt_id", ["sample_id", "read_alt_id"]);

=head1 RELATIONS

=head2 sample

Type: belongs_to

Related object: L<Sfams::Schema::Result::Sample>

=cut

__PACKAGE__->belongs_to(
  "sample",
  "Sfams::Schema::Result::Sample",
  { sample_id => "sample_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 orfs

Type: has_many

Related object: L<Sfams::Schema::Result::Orf>

=cut

__PACKAGE__->has_many(
  "orfs",
  "Sfams::Schema::Result::Orf",
  { "foreign.read_id" => "self.read_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:B6FkF1o7JlMScHFjANi3Kg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
