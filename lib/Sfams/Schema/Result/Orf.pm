package Sfams::Schema::Result::Orf;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Orf

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
);
__PACKAGE__->set_primary_key("orf_id");
__PACKAGE__->add_unique_constraint("sample_id_orf_alt_id", ["sample_id", "orf_alt_id"]);

=head1 RELATIONS

=head2 familymembers

Type: has_many

Related object: L<Sfams::Schema::Result::Familymember>

=cut

__PACKAGE__->has_many(
  "familymembers",
  "Sfams::Schema::Result::Familymember",
  { "foreign.orf_id" => "self.orf_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 read

Type: belongs_to

Related object: L<Sfams::Schema::Result::Metaread>

=cut

__PACKAGE__->belongs_to(
  "read",
  "Sfams::Schema::Result::Metaread",
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

Related object: L<Sfams::Schema::Result::Sample>

=cut

__PACKAGE__->belongs_to(
  "sample",
  "Sfams::Schema::Result::Sample",
  { sample_id => "sample_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 searchresults

Type: has_many

Related object: L<Sfams::Schema::Result::Searchresult>

=cut

__PACKAGE__->has_many(
  "searchresults",
  "Sfams::Schema::Result::Searchresult",
  { "foreign.orf_id" => "self.orf_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:1wDZZZzLQDrlAbiV7MI7nw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
