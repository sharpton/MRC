use utf8;
package SFams::Schema::Result::Analysis;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::Analysis

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<analysis>

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

=head1 PRIMARY KEY

=over 4

=item * L</analysisid>

=back

=cut

__PACKAGE__->set_primary_key("analysisid");

=head1 RELATIONS

=head2 famid

Type: belongs_to

Related object: L<SFams::Schema::Result::Family>

=cut

__PACKAGE__->belongs_to(
  "famid",
  "SFams::Schema::Result::Family",
  { famid => "famid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 treeid

Type: belongs_to

Related object: L<SFams::Schema::Result::Tree>

=cut

__PACKAGE__->belongs_to(
  "treeid",
  "SFams::Schema::Result::Tree",
  { treeid => "treeid" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:suk1Bh4rDjkNDUjt1ge4Wg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
