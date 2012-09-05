package Sfams::Schema::Result::Analysis;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Analysis

=cut

__PACKAGE__->table("analysis");

=head1 ACCESSORS

=head2 analysisid

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 project_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 famid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 treeid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 statistics

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "analysisid",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "project_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "famid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "treeid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "statistics",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("analysisid");

=head1 RELATIONS

=head2 famid

Type: belongs_to

Related object: L<Sfams::Schema::Result::Family>

=cut

__PACKAGE__->belongs_to(
  "famid",
  "Sfams::Schema::Result::Family",
  { famid => "famid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 treeid

Type: belongs_to

Related object: L<Sfams::Schema::Result::Tree>

=cut

__PACKAGE__->belongs_to(
  "treeid",
  "Sfams::Schema::Result::Tree",
  { treeid => "treeid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:BY+ETWnY/S+UDV3UxmPZuw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
