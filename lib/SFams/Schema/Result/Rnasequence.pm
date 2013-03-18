use utf8;
package SFams::Schema::Result::Rnasequence;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Rnasequence

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<rnasequences>

=cut

__PACKAGE__->table("rnasequences");

=head1 ACCESSORS

=head2 sequence_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 alt_sequence_id

  data_type: 'varchar'
  is_nullable: 0
  size: 25

=head2 type

  data_type: 'enum'
  extra: {list => ["ssu","lsu"]}
  is_nullable: 0

=head2 start

  data_type: 'integer'
  is_nullable: 1

Start coordinate

=head2 end

  data_type: 'integer'
  is_nullable: 1

End coordinate

=head2 sampleid

  data_type: 'integer'
  is_nullable: 1

=head2 sequence

  accessor: undef
  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "sequence_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "alt_sequence_id",
  { data_type => "varchar", is_nullable => 0, size => 25 },
  "type",
  {
    data_type => "enum",
    extra => { list => ["ssu", "lsu"] },
    is_nullable => 0,
  },
  "start",
  { data_type => "integer", is_nullable => 1 },
  "end",
  { data_type => "integer", is_nullable => 1 },
  "sampleid",
  { data_type => "integer", is_nullable => 1 },
  "sequence",
  { accessor => undef, data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</sequence_id>

=back

=cut

__PACKAGE__->set_primary_key("sequence_id");


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:5SddnIKv3ijxVSzwK4S3XA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
