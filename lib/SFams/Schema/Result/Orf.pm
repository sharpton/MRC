use utf8;
package SFams::Schema::Result::Orf;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Orf

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<orfs>

=cut

__PACKAGE__->table("orfs");

=head1 ACCESSORS

=head2 orf_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 sample_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 read_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 orf_alt_id

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 start

  data_type: 'integer'
  is_nullable: 1

=head2 stop

  data_type: 'integer'
  is_nullable: 1

=head2 frame

  data_type: 'enum'
  extra: {list => [0,1,2]}
  is_nullable: 1

=head2 strand

  data_type: 'enum'
  extra: {list => ["-","+"]}
  is_nullable: 1

=head2 seq

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "orf_id",
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
  "read_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "orf_alt_id",
  { data_type => "varchar", is_nullable => 0, size => 256 },
  "start",
  { data_type => "integer", is_nullable => 1 },
  "stop",
  { data_type => "integer", is_nullable => 1 },
  "frame",
  { data_type => "enum", extra => { list => [0, 1, 2] }, is_nullable => 1 },
  "strand",
  { data_type => "enum", extra => { list => ["-", "+"] }, is_nullable => 1 },
  "seq",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</orf_id>

=back

=cut

__PACKAGE__->set_primary_key("orf_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<sample_id_orf_alt_id>

=over 4

=item * L</sample_id>

=item * L</orf_alt_id>

=back

=cut

__PACKAGE__->add_unique_constraint("sample_id_orf_alt_id", ["sample_id", "orf_alt_id"]);

=head1 RELATIONS

=head2 familymembers

Type: has_many

Related object: L<SFams::Schema::Result::Familymember>

=cut

__PACKAGE__->has_many(
  "familymembers",
  "SFams::Schema::Result::Familymember",
  { "foreign.orf_id" => "self.orf_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 read

Type: belongs_to

Related object: L<SFams::Schema::Result::Metaread>

=cut

__PACKAGE__->belongs_to(
  "read",
  "SFams::Schema::Result::Metaread",
  { read_id => "read_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
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

=head2 searchresults

Type: has_many

Related object: L<SFams::Schema::Result::Searchresult>

=cut

__PACKAGE__->has_many(
  "searchresults",
  "SFams::Schema::Result::Searchresult",
  { "foreign.orf_id" => "self.orf_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:UXTZFPXZrH3EctscJHFU/g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
