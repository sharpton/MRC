use utf8;
package SFams::Schema::Result::Metaread;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Metaread

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<metareads>

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

=head2 seq

  data_type: 'text'
  is_nullable: 1

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
  "seq",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</read_id>

=back

=cut

__PACKAGE__->set_primary_key("read_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<sample_id_read_alt_id>

=over 4

=item * L</sample_id>

=item * L</read_alt_id>

=back

=cut

__PACKAGE__->add_unique_constraint("sample_id_read_alt_id", ["sample_id", "read_alt_id"]);

=head1 RELATIONS

=head2 orfs

Type: has_many

Related object: L<SFams::Schema::Result::Orf>

=cut

__PACKAGE__->has_many(
  "orfs",
  "SFams::Schema::Result::Orf",
  { "foreign.read_id" => "self.read_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 sample

Type: belongs_to

Related object: L<SFams::Schema::Result::Sample>

=cut

__PACKAGE__->belongs_to(
  "sample",
  "SFams::Schema::Result::Sample",
  { sample_id => "sample_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:PD60IlmDBOI/WkOxIq96rw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
