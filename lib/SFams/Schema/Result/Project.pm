use utf8;
package SFams::Schema::Result::Project;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Project

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<project>

=cut

__PACKAGE__->table("project");

=head1 ACCESSORS

=head2 project_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 64

=head2 description

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "project_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 64 },
  "description",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</project_id>

=back

=cut

__PACKAGE__->set_primary_key("project_id");

=head1 RELATIONS

=head2 samples

Type: has_many

Related object: L<SFams::Schema::Result::Sample>

=cut

__PACKAGE__->has_many(
  "samples",
  "SFams::Schema::Result::Sample",
  { "foreign.project_id" => "self.project_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rBUuHoMxIn6yvFo0UEE/iA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
