use utf8;
package SFams::Schema::Result::Familyconstruction;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Familyconstruction

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<familyconstruction>

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

descripton of how the family was created

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

=head1 PRIMARY KEY

=over 4

=item * L</familyconstruction_id>

=back

=cut

__PACKAGE__->set_primary_key("familyconstruction_id");

=head1 RELATIONS

=head2 families

Type: has_many

Related object: L<SFams::Schema::Result::Family>

=cut

__PACKAGE__->has_many(
  "families",
  "SFams::Schema::Result::Family",
  { "foreign.familyconstruction_id" => "self.familyconstruction_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yowhSOgieSTpUqfc62Zi1g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
