package IMG::Schema::Result::Rnasequence;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

IMG::Schema::Result::Rnasequence

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

=head2 end

  data_type: 'integer'
  is_nullable: 1

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
__PACKAGE__->set_primary_key("sequence_id");


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-03-14 16:34:50
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:RjJIREKYsxdGDpNI/fE8wA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
