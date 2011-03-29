package IMG::Schema::Result::Familyconstruction;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

IMG::Schema::Result::Familyconstruction

=cut

__PACKAGE__->table("familyconstruction");

=head1 ACCESSORS

=head2 familyconstruction_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 50

=head2 author

  data_type: 'varchar'
  is_nullable: 0
  size: 30

=cut

__PACKAGE__->add_columns(
  "familyconstruction_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 50 },
  "author",
  { data_type => "varchar", is_nullable => 0, size => 30 },
);
__PACKAGE__->set_primary_key("familyconstruction_id");

=head1 RELATIONS

=head2 families

Type: has_many

Related object: L<IMG::Schema::Result::Family>

=cut

__PACKAGE__->has_many(
  "families",
  "IMG::Schema::Result::Family",
  { "foreign.familyconstruction_id" => "self.familyconstruction_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2011-03-14 16:34:50
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:vKybhYBM3j6QG6N/u8mMLg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
