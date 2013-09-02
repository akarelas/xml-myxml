Two modules are included in this distribution.

XML::MyXML is deprecated, not maintained anymore, and only included so that older programs using it continue to work.

XML::MyXML::II is similary to XML::MyXML, but newer, maintained, and improved. It's the module you should use. It's differences from XML::MyXML are:

 * Better unicode support
 * Automatic object destruction, when object goes out of scope
 * Removed the 'soft' and 'utf8' options from functions and methods
 * the object tag method doesn't by default strip the namespace from the returned tagname

You can find this module's documentation on CPAN here: https://metacpan.org/module/XML::MyXML::II
