use utf8;
package SFams::Schema::Result::FamilymembersSlim;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

SFams::Schema::Result::FamilymembersSlim

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<familymembers_slim>

=cut

__PACKAGE__->table("familymembers_slim");

=head1 ACCESSORS

=head2 familymember_id_slim

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 famid_slim

  data_type: 'integer'
  is_nullable: 0

=head2 orf_alt_id_slim

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 sample_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 classification_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "familymember_id_slim",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "famid_slim",
  { data_type => "integer", is_nullable => 0 },
  "orf_alt_id_slim",
  { data_type => "varchar", is_nullable => 0, size => 256 },
  "sample_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "classification_id",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</familymember_id_slim>

=back

=cut

__PACKAGE__->set_primary_key("familymember_id_slim");

=head1 UNIQUE CONSTRAINTS

=head2 C<orf_fam_sample_class_id>

=over 4

=item * L</orf_alt_id_slim>

=item * L</famid_slim>

=item * L</sample_id>

=item * L</classification_id>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "orf_fam_sample_class_id",
  [
    "orf_alt_id_slim",
    "famid_slim",
    "sample_id",
    "classification_id",
  ],
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-03-02 15:04:01
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:a5q8oBEp1dUQoifVaXqMVQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
