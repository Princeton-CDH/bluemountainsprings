xquery version "3.0";
(:~
 : This module provides the functions supporting the Blue Mountain Springs
 : API.
 :
 : The first part of the module contains utility functions that access the underlying
 : database and its objects.
 :
 : The second part of the module contains resource functions conforming with the 
 : RESTXQ 1.0 specification for writing RESTful services in XQuery.
 :
 : @see http://www.exquery.org/
 : @see http://exquery.github.io/exquery/exquery-restxq-specification/restxq-1.0-specification.html
 : @author Clifford Wulfman
 : @version 1.0.0
 :)
module namespace springs = "http://bluemountain.princeton.edu/apps/springs";

import module namespace config="http://bluemountain.princeton.edu/apps/springs/config" at "config.xqm";
import module namespace request = "http://exist-db.org/xquery/request";
import module namespace response = "http://exist-db.org/xquery/response";
import module namespace rest = "http://exquery.org/ns/restxq" ;

declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace http = "http://expath.org/ns/http-client"; 
declare namespace tei="http://www.tei-c.org/ns/1.0";

(: Global Declarations :)

(:~
 : The class identifier for Blue Mountain Issues.
 :
 : Blue Mountain Objects are classified in the TEI header according to
 : the Getty Art and Architecture Thesaurus.
 : 
 : In the current implementation, there are two kinds of objects:
 : <ul>
 : <li>http://vocab.getty.edu/aat/300215389: magazines (periodicals)</li>
 : <li>http://vocab.getty.edu/aat/300312349: issues (object groupings)</li>
 : </ul>
 :
 : @see http://vocab.getty.edu/aat/
 :)
declare variable $springs:issueClass as xs:string := "300312349";
declare variable $springs:magazineClass as xs:string := "300215389";

(:~
 : Emitting csv requires terminating each line with a linefeed character.
 :)
declare variable $springs:lf as xs:string := codepoints-to-string(10);



(:::::::::::::::::::: UTILITY FUNCTIONS ::::::::::::::::::::)

(:~
 : The Blue Mountain Object identified by an ID.
 :
 : Blue Mountain objects -- magazines and issues -- are
 : distinguished by a unique identifier: a bmtnid. The composition
 : of a bmtnid is discussed in detail elsewhere.
 :
 : To retrieve a Blue Mountain object from the database, therefore,
 : one queries for an object with a matching bmtnid.
 :
 : @param $bmtnid the id of the object to be retrieved
 : @return the TEI document for the object
 :)
declare function springs:_bmtn-object($bmtnid as xs:string)
as element()
{
    collection($config:transcriptions)//tei:idno[@type='bmtnid' and . = $bmtnid]/ancestor::tei:TEI
};


(:~
 : The type of a given Blue Mountain Object.
 :
 : Blue Mountain Objects are classified in the TEI header according to
 : the Getty Art and Architecture Thesaurus.
 : 
 : In the current implementation, there are two kinds of objects:
 : <ul>
 : <li>http://vocab.getty.edu/aat/300215389: magazines (periodicals)</li>
 : <li>http://vocab.getty.edu/aat/300312349: issues (object groupings)</li>
 : </ul>
 :
 : The implementation does not specify what kinds of objects may be in
 : Blue Mountain.
 :
 : @see http://vocab.getty.edu/aat/
 : @param $bmtnid the id of the Object whose type is being determined
 : @return a string identifying the Object's type.
 :)
declare function springs:_typeof($bmtnid as xs:string)
as xs:string
{
    xs:string(springs:_bmtn-object($bmtnid)//tei:teiHeader//tei:profileDesc/tei:textClass/tei:classCode)
};


(:~
 : The ID of a given Blue Mountain Object.
 :
 : Every Blue Mountain Object has a unique identifier. This identifier
 : is encoded in a tei:idno element whose type is 'bmtnid'.
 :
 : @param $bmtnobject a TEI element
 : @return a string representing the supplied parameter's id.
 :)
declare function springs:_bmtnid-of($bmtnobject as element())
as xs:string
{
    $bmtnobject//tei:TEI//tei:teiHeader/tei:fileDesc/tei:publicationStmt/tei:idno[@type='bmtnid']
};


(:~
 : Is an Object with a given ID an issue?
 :
 : Some module logic depends on the type of Object being evaluated:
 : a Magazine object or an Issue object. This predicate hides the 
 : procedure for determining that an object is an issue.
 :
 : @param $bmtnid a string representing a Blue Mountain Object's id
 : @return boolean true if the associated object is an issue; false otherwise
 :)
declare function springs:_issuep($bmtnid as xs:string)
as xs:boolean
{
    if (springs:_typeof($bmtnid) = $springs:issueClass) then true() else false() 
};


(:~
 : The primary descriptive metadata element of a Blue Mountain Object.
 :
 : This function serves as a macro for the xpath to the tei:monogr element
 : of a object.
 : 
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-monogr.html
 : @param $magazine a TEI element
 : @return a tei:monogr element
 :)
declare function springs:_magazine-monogr($magazine as element())
as element()
{
    $magazine/tei:teiHeader/tei:fileDesc/tei:sourceDesc/tei:biblStruct/tei:monogr
};


(:~
 : The display-formatted version of a title.
 :
 : A tei:title may contain a number of sub-elements. This function
 : parses them into a string that can be used to display the title
 : of the object.
 :
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-title.html
 : @param $title a tei:title element
 : @return a string
 :)
declare function springs:_formatted-title($title as element())
as xs:string
{
    let $nonSort := $title/tei:seg[@type='nonSort']
    let $main := $title/tei:seg[@type='main']
    let $sub  := $title/tei:seg[@type='sub']
    let $titleString := string-join(($nonSort,$main), ' ')
    return if ($sub) then $titleString || ': ' || $sub else $titleString
};

(:~
 : The display title of a Blue Mountain Object.
 :
 : A wrapper around a call to springs:_formatted-title($title) with
 : the 'j' level title as an argument.
 :
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-title.html
 :)
declare function springs:_object-title($object as element())
as xs:string
{
    springs:_formatted-title(springs:_magazine-monogr($object)/tei:title[@level='j'])
};


(:~
 : The constituent with a particular constituent id.
 :
 : The text body of an Issue Object contains tei:divs corresponding
 : to the relatedItems in the teiHeader's source description. This function
 : retrieves an Issue Object and extracts the tei:div corresponding to the
 : given id.
 :
 : @param $objid a bmtnid
 : @param $constid the id of a constituent of the given object.
 : @return a tei:div element
 :)
declare function springs:_constituent($objid as xs:string, $constid as xs:string)
as element()
{
    springs:_bmtn-object($objid)//tei:div[@corresp = $constid]
};


(:~
 : The id of an issue constituent (tei:relatedItem type='constituent']).
 :
 : The descriptive bibliographic information for the articles, advertisements,
 : and other content of a magazine issue are encoded in the teiHeader as a series
 : of tei:relatedItems. Each of these relatedItems has an xml:id; this id is used
 : to link the bibliographic information about a constituent with its representation
 : in the body of the document.
 :
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-sourceDesc.html
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-biblStruct.html
 : @param $constituent a tei:relatedItem element
 : @return the xml:id of that element
 :)
declare function springs:_constituent-id($constituent as element())
as xs:string
{
    xs:string($constituent/@xml:id)
};


(:~
 : The display title of an issue constituent.
 :
 : A wrapper around a call to springs:_formatted-title($title) with
 : the first 'a' level title as an argument.
 :
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-title.html
 :)    
declare function springs:_constituent-title($constituent as element())
as xs:string
{
    springs:_formatted-title($constituent/tei:biblStruct[1]/tei:analytic[1]/tei:title[@level = 'a'][1])   
};


(:~
 : The publication date of a Blue Mountain Object.
 :
 : The publication date is encoded as a tei:date in the
 : tei:imprint of the object in its teiHeader. 
 :
 : @see http://www.tei-c.org/release/doc/tei-p5-doc/en/html/ref-imprint.html
 : @param $bmtnobj a tei:TEI element
 : @return a tei:date element
 :)
declare function springs:_object-date($bmtnobj as element())
as element()
{
    springs:_magazine-monogr($bmtnobj)/tei:imprint/tei:date
};


(:~
 : The issuance date of an issue.
 :
 : Sometimes an issue has a specific issuance date; in the
 : case of an issue whose issuance date is a range (of weeks, months)
 : Blue Mountain defines its issuance date as the first date in the range.
 :
 : @param $issueobj a TEI element
 : @return a w3cdtf-formatted date string.
 :)
declare function springs:_issue-date($issueobj as element())
as xs:string
{
    let $date := springs:_object-date($issueobj)
    return if ($date/@from) then $date/@from else $date/@when    
};


(:~
 : The start date of a magazine run.
 :
 : Magazine objects encode their run dates as
 : date @from="yyyy-mm-dd" @to="yyyy-mm-dd";
 : if there was only one issue, the run is
 : encoded as date @when="yyyy-mm-dd", in which case
 : the @when date is used for both the beginning and
 : the end of the run.
 :
 : @param $magazine a TEI element
 : @return a w3cdtf-formatted date string.
 :)
declare function springs:_magazine-date-start($magazine as element())
as xs:string
{
    let $date := springs:_object-date($magazine)
    return if ($date/@from) then $date/@from else $date/@when
};


(:~
 : The end date of a magazine run.
 :
 : @see documentation for springs:_magazine-date-start()
 : @param $magazine a TEI element
 : @return a w3cdtf-formatted date string.
 :)
declare function springs:_magazine-date-end($magazine as element())
as xs:string
{
    let $date := springs:_object-date($magazine)
    return if ($date/@to) then $date/@to else $date/@when
};


(:~
 : The issues of a Magazine
 :
 : The issues of a magazine M are defined as all tei:TEI elements
 : having M as the host.
 :
 : @param $magid a bmtnid
 : @return a sequence of 0 or more TEI elements
 :)
declare function springs:_issues-of-magazine($magid as xs:string)
as element()*
{
    collection($config:transcriptions)//tei:relatedItem[@type='host' and @target = $magid]/ancestor::tei:TEI
};


(:~
 : All the Magazine objects in Blue Mountain.
 :
 : Magazine objects are TEI elements whose tei:classCode is $springs:magazineClass.
 : @return sequence of tei:TEI elements.
 :)
declare function springs:_magazines()
as element()+
{
    collection($config:transcriptions)//tei:TEI[./tei:teiHeader/tei:profileDesc/tei:textClass/tei:classCode = $springs:magazineClass ]
};

(:~
 : A common representation of a magazine that can be serialized different ways.
 :
 : The common data model for a magazine used by Blue Mountain Springs. It is serialized
 : in different formats by the RESTXQ functions.
 :
 : @param $bmtnobj a tei:TEI element representing a Magazine Object
 : @param $include-issues as boolean flag; if true include a representation of all issues
 : @return a magazine element
 :)
declare function springs:_magazine-struct($bmtnobj as element(), $include-issues as xs:boolean)
as element()
{
    let $bmtnid := springs:_bmtnid-of($bmtnobj)
    let $primaryTitle := springs:_object-title($bmtnobj)
    let $primaryLanguage := $bmtnobj/tei:teiHeader/tei:profileDesc/tei:langUsage/tei:language[1]/@ident
    let $startDate := springs:_magazine-date-start($bmtnobj)
    let $endDate := springs:_magazine-date-end($bmtnobj)
    let $uri := $config:springs-root || '/magazines/' || $bmtnid
    let $issues :=
        if ($include-issues) then
              for $issue in springs:_issues-of-magazine($bmtnid)
              return
                springs:_issue-struct($issue, false())
        else ()
    return
        <magazine>
            <bmtnid>{ $bmtnid }</bmtnid>
            <primaryTitle>{ $primaryTitle }</primaryTitle>
            <primaryLanguage>{ $primaryLanguage }</primaryLanguage>
            <startDate>{ $startDate }</startDate>
            <endDate>{ $endDate }</endDate>
            <uri>{ $uri }</uri>
            { for $issue in $issues return $issue }
        </magazine>
};


(:~
 : A common representation of an issue that can be serialized different ways.
 :
 : The common data model for an issue used by Blue Mountain Springs. It is serialized
 : in different formats by the RESTXQ functions.
 :
 : @param $bmtnobj a tei:TEI element representing a Magazine Object
 : @param $include-constituents a boolean if true, include all constituents
 : @return an issue element
 :)
declare function springs:_issue-struct($bmtnobj as element(), $include-constituents as xs:boolean)
as element()
{
    let $bmtnid := springs:_bmtnid-of($bmtnobj)
    return
     <issue>
        <id>  { $bmtnid }</id>
        <date>{ springs:_issue-date($bmtnobj) }</date>
        <url> { $config:springs-root || '/issues/' || $bmtnid }</url>
       {
         if ($include-constituents) then
            for $constituent in $bmtnobj//tei:relatedItem[@type='constituent']
            return
           <constituent>
           <id>{ string-join(($bmtnid,springs:_constituent-id($constituent)), '#') }</id>
           <uri>{ $config:springs-root || '/constituent/' || $bmtnid || '/' || springs:_constituent-id($constituent) }</uri>
           <title>{ springs:_constituent-title($constituent) }</title>
           {
               for $stmt in $constituent//tei:respStmt
               return <byline>{ normalize-space($stmt/tei:persName/text()) }</byline>
           }
        </constituent>
        else ()
       }
     </issue>
};


(:::: Utilities for Contributors ::::)
declare function springs:_contributor-data($issue as element())
as xs:string*
{
    let $issueid := xs:string($issue//tei:idno[@type='bmtnid'])
    let $issuelabel := $issue//tei:sourceDesc/tei:biblStruct/tei:monogr/tei:title/tei:seg[@type='main']
    let $contributions := $issue//tei:relatedItem[@type='constituent']
    for $contribution in $contributions
        let $constituentid := xs:string($contribution/@xml:id)
        let $title := springs:_constituent-title($contribution)
        let $qtitle := concat("&quot;", $title,"&quot;")
        let $respStmts := $contribution//tei:respStmt
        for $stmt in $respStmts
            let $byline := normalize-space($stmt/tei:persName/text())
            let $byline := concat("&quot;", $byline,"&quot;")
            let $contributorid := if ($stmt/tei:persName/@ref) then xs:string($stmt/tei:persName/@ref) else " "
            return
             concat(string-join(($issueid, $issuelabel,$contributorid,$byline,$constituentid,$qtitle), ','), $springs:lf)
};


declare function springs:_contributors-to($bmtnid as xs:string)
as xs:string*
{
    let $header := concat(string-join(('bmtnid', 'label', 'contributorid', 'byline', 'constituentid', 'title'),','), $springs:lf)
    let $records :=
        if (springs:_issuep($bmtnid))
            then springs:_contributor-data(springs:_bmtn-object($bmtnid))
        else 
            for $issue in springs:_issues-of-magazine($bmtnid)
            return springs:_contributor-data($issue)
    return
         ($header,$records)
};

(:::::::::::::::::::: END OF UTILITY FUNCTIONS ::::::::::::::::::::)




(:::::::::::::::::::: RESOURCE FUNCTIONS ::::::::::::::::::::)

(:~
 : Resource Functions
 : 
 : The Blue Mountain Springs API is implemented as a suite of
 : XQuery Resource Functions as defined by the RESTXQ specification.
 : That specification uses XQuery 3.0 annotations to associate
 : xquery functions with HTTP interactions.
 :
 : When enabled in eXist-db, RESTXQ establishes a registry of 
 : resource functions in the database and routes HTTP requests to
 : the matching functions. RESTXQ enables content negotiation by
 : supporting annotations that specify what content type a function
 : produces. Different functions can be written to handle different
 : content specifications.
 : 
 : @see http://exquery.github.io/exquery/exquery-restxq-specification/restxq-1.0-specification.html
 :)


(:~
 : /springs/api
 :
 : The top level of the service; it returns an XML
 : document detailing the API.
 :
 : @see http://exquery.github.io/exquery/exquery-restxq-specification/restxq-1.0-specification.html#rest-resource-functions
 :)
declare
 %rest:GET
 %rest:path("/springs/api")
function springs:top()
{
    exrest:find-resource-functions(xs:anyURI('/db/apps/bmtnsprings/modules/springs.xqm'))
};




(:~
 : The magazines/ service.
 :
 : Blue Mountain contains magazines. The magazines/
 : service returns representations of those magazines.
 :
 : If no resource is specified, the service returns a
 : representation of all the magazines in Blue Mountain.
 :
 : If a resource is specified (as a bmtnid), the service
 : returns a representation of the corresponding magazine.
 :
 : Blue Mountain Springs supports cross-origin resource sharing
 : (CORS) by specifying Access-Control-Allow-Origin: * in the
 : response header.
 :
 : The HTTP response header is only basic in Springs 1.0.
 :)

(:~
 : magazines/ as JSON
 :
 : Queries the database for magazines and generates
 : a magazine-struct for each. It uses eXist's built-in
 : JSON serializer to convert the magazine-struct XML
 : into JSON.
 : 
 : @return a result sequence (rest:response, magazines)
 :)
declare
 %rest:GET
 %rest:path("/springs/magazines")
 %output:method("json")
 %rest:produces("application/json")
function springs:magazines-as-json() 
as item()+ 
{
    let $response :=
      <magazines> {
        for $mag in springs:_magazines()
        return springs:_magazine-struct($mag, false())
    } </magazines>
    return 
         (<rest:response>
            <http:response>
              <http:header name="Content-Type" value="application/json"/>
              <http:header name="Access-Control-Allow-Origin" value="*"/>
            </http:response>
          </rest:response>,
         $response)
};


(:~
 : magazines/ as text/CSV
 :
 : Queries the database for magazines and generates
 : a magazine-struct for each. It assembles a return
 : value by converting each magazine-struct into a
 : comma-separated string.
 :
 : @return a result sequence (<rest:response/>, text)
 :)
declare
 %rest:GET
 %rest:path("/springs/magazines")
 %output:method("text")
 %rest:produces("text/csv")
function springs:magazines-as-csv()
as item()+
{
    let $response :=
      for $mag in springs:_magazines()
      let $struct := springs:_magazine-struct($mag, false())
      return concat(string-join(($struct/bmtnid,
                                 $struct/primaryTitle,
                                 $struct/primaryLanguage,
                                 $struct/startDate,
                                 $struct/endDate,
                                 $struct/uri), ','), $springs:lf)
    return
        (<rest:response>
           <http:response>
             <http:header name="Content-Type" value="text/csv"/>
             <http:header name="Access-Control-Allow-Origin" value="*"/>
           </http:response>
         </rest:response>,
         $response)
};


(:~
 : magazines/$bmtnid
 :
 : When the Blue Mountain ID of a magzine is supplied
 : as a resource to the magazines/ service, it returns a
 : representation of that magazine.
 :
 : In Blue Mountain Springs 1.0, the only representation
 : available is a JSON expression of the magazine-struct.
 :
 : @param $bmtnid a Blue Mountain ID of a magazine
 : @return a sequence (rest:response, json)
 :)
declare
  %rest:GET
  %rest:path("/springs/magazines/{$bmtnid}")
  %output:method("json")
  %rest:produces("application/json")
function springs:magazine-as-json($bmtnid as xs:string) 
as item()+
{
    let $response := springs:_magazine-struct(springs:_bmtn-object($bmtnid), true())
    return 
         (<rest:response>
            <http:response>
              <http:header name="Content-Type" value="application/json"/>
              <http:header name="Access-Control-Allow-Origin" value="*"/>
            </http:response>
          </rest:response>,
         $response)
};  
  



(:~
 : The issues/ service.
 :
 : The issues/ service returns representations of magazine issues.
 : The service behaves differently depending on the kind of
 : resource that is requested:
 : <ol>
 : <li>if the resource is an issue, the service returns a representation
 :     of the issue.</li>
 :<li>if the resource is a magazine, the service returns representations
 :    of all the issues of that magazine.</li>
 :</ol>
 :)

(:~
 : issues/$bmtnid as TEI
 :
 : If the requested resource is an issue,
 : return the tei:TEI document in the database.
 :
 : If the requested resource is a magazine,
 : return a teiCorpus object containing
 : the TEI documents for all the magazine's
 : issues.
 :
 : For large magazine runs, this service will 
 : return a very large data set in Blue Mountain 1.0.
 : A future version will use status 413 to indicate
 : an excessively large response and compress the response
 : before transmission or implement status 207 to coordinate
 : partial file tranfers.
 :
 : @param $bmtnid an id of a magazine or an issue
 : @return a sequence (rest:response, xml)
 :)
declare
  %rest:GET
  %rest:path("/springs/issues/{$bmtnid}")
  %rest:produces("application/tei+xml")
function springs:issue-as-tei($bmtnid as xs:string)
as item()+
{
    let $response :=
       if (springs:_issuep($bmtnid)) then
            springs:_bmtn-object($bmtnid)
        else
       <teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
         <teiHeader>
             <fileDesc>
                 <titleStmt>
                     <title>{ springs:_object-title(springs:_bmtn-object($bmtnid)) }</title>
                </titleStmt>
	           <publicationStmt>
	               <p>Publication Information</p>
	            </publicationStmt>
	           <sourceDesc>
	               <p>Information about the source</p>
	            </sourceDesc>
           </fileDesc>
         </teiHeader>
          { springs:_issues-of-magazine($bmtnid) }
       </teiCorpus>
     return
         (<rest:response>
            <http:response>
              <http:header name="Content-Type" value="application/tei+xml"/>
              <http:header name="Access-Control-Allow-Origin" value="*"/>
            </http:response>
          </rest:response>,
         $response)
};


(:~
 : issues/$bmtnid as plain text
 :
 : If the requested resource is an issue,
 : the service retrieves the issue tei:TEI 
 : document from the database and converts it
 : to plain text using a simple xslt transformation.
 :
 : If the requested resource is a magazine,
 : the service iterates over all the issues in the
 : magazine and returns a single bag of words representing
 : the text of the entire run.
 :
 : For large magazine runs, this service will 
 : return a very large data set in Blue Mountain 1.0.
 : A future version will use status 413 to indicate
 : an excessively large response and compress the response
 : before transmission or implement status 207 to coordinate
 : partial file tranfers.
 :
 : @param $bmtnid an id of a magazine or issue
 : @return a sequence (rest:response, text)
 :)
declare
  %rest:GET
  %rest:path("/springs/issues/{$bmtnid}")
  %output:method("text")
  %rest:produces("text/plain")
function springs:issue-as-plaintext($bmtnid as xs:string) 
as item()+
{
    let $xsl := doc($config:app-root || "/resources/xsl/tei2txt.xsl")
    let $responseBody :=
        if (springs:_issuep($bmtnid)) then
            transform:transform( springs:_bmtn-object($bmtnid), $xsl, () )
        else
            for $issue in springs:_issues-of-magazine($bmtnid)
            return transform:transform($issue, $xsl, ())
    return
        (<rest:response>
          <http:response>
            <http:header name="Content-Type" value="text/plain"/>
            <http:header name="Access-Control-Allow-Origin" value="*"/>
          </http:response>
         </rest:response>,
         $responseBody)
};



(:~
 : issues/$bmtnid as JSON
 :
 : If the requested resource is an issue,
 : the service retrieves the issue tei:TEI 
 : document from the database and converts it
 : to plain text using an xslt transformation.
 :
 : If the requested resource is a magazine,
 : the service iterates over all the issues in the
 : magazine and returns a single structure representing
 : the text of the entire run.
 :
 : For large magazine runs, this service will 
 : return a very large data set in Blue Mountain 1.0.
 : A future version will use status 413 to indicate
 : an excessively large response and compress the response
 : before transmission or implement status 207 to coordinate
 : partial file tranfers.
 :
 : @param $bmtnid an id of a magazine or issue
 : @return a sequence (rest:response, text)
 :)
declare
  %rest:GET
  %rest:path("/springs/issues/{$bmtnid}")
  %output:method("json")
  %rest:produces("application/json")
function springs:issue-as-json($bmtnid as xs:string) 
as item()+
{
    let $xsl := doc($config:app-root || "/resources/xsl/tei2data.xsl")
    let $xslt-parameters := 
      <parameters>
          <param name="springs-root" value="{$config:springs-root}"/>
      </parameters>
    let $responseBody :=
        if (springs:_issuep($bmtnid)) then
            transform:transform( springs:_bmtn-object($bmtnid), $xsl, $xslt-parameters )
        else
            springs:_magazine-struct(springs:_bmtn-object($bmtnid), true())
    return 
             (<rest:response>
               <http:response>
                <http:header name="Content-Type" value="application/json"/>
                <http:header name="Access-Control-Allow-Origin" value="*"/>
               </http:response>
              </rest:response>,
              $responseBody)
};


(:~
 : issues/$bmtnid as RDF
 :
 : In Blue Mountain version 1.0, this
 : service is aimed primarily at the
 : MODNETS aggregator, and it provides
 : an RDF representation that complies
 : with its requirements: COLLEX-flavored
 : RDF.
 :
 : @see http://www.modnets.org/
 : @see http://wiki.collex.org/index.php/Submitting_RDF
 :
 : If the requested resource is an issue,
 : the service retrieves the issue tei:TEI 
 : document from the database and converts it
 : to RDF using an xslt transformation.
 :
 : If the requested resource is a magazine,
 : the service iterates over all the issues in the
 : magazine and returns a single structure representing
 : the text of the entire run.
 :
 : @param $bmtnid an id of a magazine or issue
 : @return a sequence (rest:response, RDF+XML)
 :)
declare
  %rest:GET
  %rest:path("/springs/issues/{$bmtnid}")
  %rest:produces("application/rdf+xml")
function springs:issue-as-rdf($bmtnid as xs:string)
as item()+
{
    let $issue := springs:_bmtn-object($bmtnid)
    let $xsl := doc($config:app-root || "/resources/xsl/bmtn2rdf.xsl")
    let $responseBody := transform:transform($issue, $xsl, ())
    return 
             (<rest:response>
               <http:response>
                <http:header name="Content-Type" value="application/rdf+xml"/>
                <http:header name="Access-Control-Allow-Origin" value="*"/>
               </http:response>
              </rest:response>,
              $responseBody)  
};



(:~
 :  constituents/ service
 :
 : The addressable portions of the magazine issues --
 : articles, illustrations, advertisements -- are the
 : issue's constituents. They are represented in two ways:
 :<ol>
 :<li>descriptive metadata about the constituent is encoded
 :    in the teiHeader as a relatedItem with an xml id attribute; 
 :</li>
 :<li>the full text of the constituent (if it is a textual
 :    constituent) is encoded in a div element linked to
 :    the metadata element with a corresp attribute.
 :</li>
 :</ol>
 :
 : The constituents service returns representations of the metadata
 : or the full text, depending on the content type requested.
 :)


(:~
 : constituents/$bmtnid as JSON
 :
 : If the specified resource is an issue,
 : the service retrieves the metadata for the
 : issue's constituents and extracts data fields.
 : If the specified resource is a magazine, 
 : extract constituents from all issues of the run.
 :
 : @param $bmtnid a magazine or issue id
 : @return a sequence (rest:response, XML)
 :)
declare
  %rest:GET
  %rest:path("/springs/constituents/{$bmtnid}")
  %output:method("json")
  %rest:produces("application/json")
function springs:constituents-as-json($bmtnid as xs:string)
as item()+
{
    let $responseBody :=
      if (springs:_issuep($bmtnid))
        then springs:_issue-struct(springs:_bmtn-object($bmtnid), true())
       else
         <issues>
            { for $issue in springs:_issues-of-magazine($bmtnid)
              return springs:_issue-struct($issue, true())
            }
         </issues>
    return
       (<rest:response>
          <http:response>
           <http:header name="Content-Type" value="application/rdf+xml"/>
           <http:header name="Access-Control-Allow-Origin" value="*"/>
          </http:response>
         </rest:response>,
         $responseBody)  
};


(:~
 : constituent/$issueid/$constid as plain text
 :
 : Return a plain-text representation of a constituent of
 : an issue by retrieving it from the database and transforming
 : it into plain text with an XSL stylesheet.
 :
 : @param $issueid the bmtnid of an issue
 : @param $constid the id of a constituent
 : @returns a sequence (rest:response, text)
 :)
declare
  %rest:GET
  %rest:path("/springs/constituent/{$issueid}/{$constid}")
  %rest:produces("text/plain")
function springs:constituent-plaintext($issueid as xs:string, $constid as xs:string)
as item()+
{

    let $constituent := springs:_constituent($issueid, $constid)
    let $xsl := doc($config:app-root || "/resources/xsl/tei2txt.xsl")
    let $responseBody := transform:transform($constituent, $xsl, ())
    return 
    (<rest:response>
       <http:response>
          <http:header name="Content-Type" value="text/plain"/>
          <http:header name="Access-Control-Allow-Origin" value="*"/>
       </http:response>
      </rest:response>,
      $responseBody)
};


(:~
 : constituent/$issueid/$constid as TEI
 :
 : Return the TEI-encoded representation of a constituent of
 : an issue by retrieving it from the database. Returns a div
 : element not an entire document.
 :
 : @param $issueid the bmtnid of an issue
 : @param $constid the id of a constituent
 : @returns a sequence (rest:response, text)
 :)
declare
  %rest:GET
  %rest:path("/springs/constituent/{$issueid}/{$constid}")
  %rest:produces("application/tei+xml")
function springs:constituent-tei($issueid, $constid) {
    (<rest:response>
       <http:response>
          <http:header name="Content-Type" value="application/tei+xml"/>
          <http:header name="Access-Control-Allow-Origin" value="*"/>
       </http:response>
      </rest:response>,
      springs:_constituent($issueid, $constid))
};


(::::::::::::::::::: TEXT ::::::::::::::::::::)
(:: I think this service is redundant ::)

declare
    %rest:GET
    %rest:path("/springs/text/{$issueid}/{$constid}")
    %output:method("text")
function springs:constituent-text($issueid as xs:string, $constid as xs:string)
{
    let $xsl := doc($config:app-root || "/resources/xsl/tei2txt.xsl")
    let $constituent := springs:_constituent($issueid, $constid)
    return transform:transform($constituent, $xsl, ())
};


declare
 %rest:GET
 %rest:path("/springs/text/{$issueid}")
function springs:text($issueid) {
    let $xsl := doc($config:app-root || "/resources/xsl/tei2txt.xsl")
    return transform:transform(springs:_bmtn-object($issueid), $xsl, ())
};


(::::::::::::::::::: CONTRIBUTORS ::::::::::::::::::::)

declare
 %rest: GET
 %rest:path("/springs/contributors/{$bmtnid}")
 %output:method("text")
 %rest:produces("text/csv")
function springs:contributors-csv($bmtnid) {
    springs:_contributors-to($bmtnid)
};


declare 
 %rest: GET
 %rest:path("/springs/contributors/{$issueid}")
 %output:method("json")
 %rest:produces("application/json")
function springs:contributors-from-issue($issueid) {
    let $issue := springs:_bmtn-object($issueid)
    let $bylines := $issue//tei:relatedItem[@type='constituent']//tei:respStmt[tei:resp = 'cre']/tei:persName
    let $issue-label := springs:_object-title($issue)
  
    return
        <contributors> {
          for $byline in $bylines
          let $contributorid := 
            if ($byline/@ref)
                then xs:string($byline/@ref)
            else ()
          let $constituent := $byline/ancestor::tei:relatedItem[@type='constituent'][1]
          let $constituentid := xs:string($constituent/@xml:id)
          let $title := if ($constituent) then springs:_constituent-title($constituent) else "Untitled"
          return
            <contributor>
                <bmtnid>{ $issueid }</bmtnid>
                <label>{ $issue-label }</label>
                <contributorid>{ $contributorid }</contributorid>
                <byline>{ xs:string($byline) }</byline>
                <contributionid>{ $constituentid }</contributionid>
                <title> { $title }</title>
            </contributor>
        } </contributors>
    
};

declare
 %rest:GET
 %rest:path("/springs/contributions")
 %rest:query-param("byline", "{$byline}", "stranger")
 %output:method("json")
 %rest:produces("application/json")
function springs:constituents-with-byline-json($byline)
as element()*
{
    <contributions> {
    for $constituent in collection($config:transcriptions)//tei:relatedItem[ft:query(.//tei:persName, $byline)]
    let $title := springs:_constituent-title($constituent)
    let $bylines := $constituent/tei:biblStruct/tei:analytic/tei:respStmt/tei:persName
    let $languages := $constituent/tei:biblStruct/tei:analytic/tei:textLang
    let $issueid := springs:_bmtnid-of($constituent/ancestor::tei:TEI)
    let $constid := xs:string($constituent/@xml:id)
    return
     <contribution>
        <title>{ $title }</title>
        { for $b in $bylines return <byline>{ xs:string($b)} </byline> }
        { for $l in $languages return <language>{ xs:string($l/@mainLang)}</language> }        
        <issue>{ xs:string($issueid) }</issue>
        <constituentid>{ $constid }</constituentid>
        <uri>{ $config:springs-root || '/constituent/' || $issueid || '/' || $constid }</uri>
     </contribution>
     } </contributions>
};

declare
 %rest:GET
 %rest:path("/springs/contributions")
 %rest:query-param("byline", "{$byline}", "stranger")
 %rest:produces("application/tei+xml")
function springs:constituents-with-byline   ($byline)
as element()*
{
    let $constituents := collection($config:transcriptions)//tei:relatedItem[ft:query(.//tei:persName, $byline)]
    return
    <teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
     <teiHeader>
         <fileDesc>
             <titleStmt>
                 <title>Blue Mountain Contributions</title>
                 <author>{ $byline }</author>
             </titleStmt>
	        <publicationStmt>
	           <p>Blue Mountain Project</p>
	        </publicationStmt>
	        <sourceDesc>
	           <biblStruct>
	           {
	               for $constituent in $constituents
	               return
	                   <relatedItem type='constituent'>
	                   { $constituent/tei:biblStruct }
	                   </relatedItem>
	           }
	           </biblStruct>
	        </sourceDesc>
         </fileDesc>
     </teiHeader> {
    for $constituent in $constituents
    let $biblStruct := $constituent/tei:biblStruct
    let $issueid := $constituent/ancestor::tei:TEI/tei:teiHeader/tei:fileDesc/tei:publicationStmt/tei:idno[@type='bmtnid']
    let $constid := xs:string($constituent/@xml:id)
    return
     <TEI xml:id="{$issueid ||'_'||$constid}">
        <teiHeader>
            <fileDesc>
            <titleStmt>
                <title>{ $biblStruct }</title>
            </titleStmt>
            <publicationStmt>
                <p>
                <ref target="{ $config:springs-root || '/constituent/' || $issueid || '/' || $constid }"/>
                </p>
            </publicationStmt>
            <seriesStmt>
                <p>Blue Mountain Project</p>
            </seriesStmt>
            <sourceDesc>{ $biblStruct }</sourceDesc>
            </fileDesc>
        </teiHeader>
        <text>
          <body>
          { $constituent/ancestor::tei:TEI//tei:div[@corresp=$constid] }
          </body>
        </text>
     </TEI>
     } </teiCorpus>
};
