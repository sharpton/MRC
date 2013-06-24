use utf8;
package MRC::Schema::Result::Searchresult;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MRC::Schema::Result::Searchresult

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<searchresults>

=cut

__PACKAGE__->table("searchresults");

=head1 ACCESSORS

=head2 searchresults_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 orf_alt_id

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 read_alt_id

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 sample_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 famid

  data_type: 'integer'
  is_nullable: 0

=head2 classification_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 0

=head2 score

  data_type: 'float'
  is_nullable: 1

=head2 evalue

  data_type: 'double precision'
  is_nullable: 1

=head2 orf_coverage

  data_type: 'float'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "searchresults_id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "orf_alt_id",
  { data_type => "varchar", is_nullable => 0, size => 256 },
  "read_alt_id",
  { data_type => "varchar", is_nullable => 0, size => 256 },
  "sample_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "famid",
  { data_type => "integer", is_nullable => 0 },
  "classification_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 0,
  },
  "score",
  { data_type => "float", is_nullable => 1 },
  "evalue",
  { data_type => "double precision", is_nullable => 1 },
  "orf_coverage",
  { data_type => "float", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</searchresults_id>

=back

=cut

__PACKAGE__->set_primary_key("searchresults_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<orf_fam_sample_class_id>

=over 4

=item * L</orf_alt_id>

=item * L</famid>

=item * L</sample_id>

=item * L</classification_id>

=back

=cut

__PACKAGE__->add_unique_constraint(
  "orf_fam_sample_class_id",
  ["orf_alt_id", "famid", "sample_id", "classification_id"],
);

=head1 RELATIONS

=head2 classification

Type: belongs_to

Related object: L<MRC::Schema::Result::ClassificationParameter>

=cut

__PACKAGE__->belongs_to(
  "classification",
  "MRC::Schema::Result::ClassificationParameter",
  { classification_id => "classification_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 sample

Type: belongs_to

Related object: L<MRC::Schema::Result::Sample>

=cut

__PACKAGE__->belongs_to(
  "sample",
  "MRC::Schema::Result::Sample",
  { sample_id => "sample_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07035 @ 2013-06-24 14:58:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:8cpJRuFnCvIQnGgbH6HVPg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
