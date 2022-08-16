unit fMain;

// TODO : prendre en charge les fichiers liés depuis les CSS
// TODO : ajouter une récupération du texte des pages (hors HTML) dans la base de données pour fournir ensuite un moteur de recherche offline
// TODO : gérer le téléchargement de tous les fichiers et ensuite leur modification une fois en local pour permettre le download sous forme de thread
interface

{$ZEROBASEDSTRINGS ON}

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, System.Rtti,
  FMX.Grid.Style, FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param,
  FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf,
  Data.Bind.EngExt, FMX.Bind.DBEngExt, FMX.Bind.Grid, System.Bindings.Outputs,
  FMX.Bind.Editors, Data.Bind.Components, Data.Bind.Grid, Data.Bind.DBScope,
  Data.DB, FireDAC.Comp.DataSet, FireDAC.Comp.Client, FMX.ScrollBox, FMX.Grid,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.Edit, FireDAC.Stan.StorageJSON,
  System.Net.URLClient, System.Net.HttpClient, System.Net.HttpClientComponent,
  FireDAC.UI.Intf, FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async,
  FireDAC.Phys, FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs, FireDAC.Phys.SQLiteWrapper.Stat, FireDAC.FMXUI.Wait,
  FireDAC.Phys.SQLiteVDataSet;

type
  TForm1 = class(TForm)
    edtURL: TEdit;
    btnGo: TButton;
    Label1: TLabel;
    Panel1: TPanel;
    StringGrid1: TStringGrid;
    tabURLDuSiteAAspirer: TFDMemTable;
    tabURLDuSiteAAspirerid: TIntegerField;
    tabURLDuSiteAAspirerURL_Source: TStringField;
    tabURLDuSiteAAspirerNom_Fichier: TStringField;
    tabURLDuSiteAAspirerEnregistree: TBooleanField;
    BindSourceDB1: TBindSourceDB;
    BindingsList1: TBindingsList;
    LinkGridToDataSourceBindSourceDB1: TLinkGridToDataSource;
    FDStanStorageJSONLink1: TFDStanStorageJSONLink;
    web: TNetHTTPClient;
    DB: TFDConnection;
    FDLocalSQL1: TFDLocalSQL;
    procedure FormCreate(Sender: TObject);
    procedure btnGoClick(Sender: TObject);
  private
    { Déclarations privées }
  public
    { Déclarations publiques }
    function ChargerURL(URL_EnCours, URL_ACharger: string): string;
    function TOAbsoluteURL(URL_EnCours, URL_ACharger: string): string;
    function ToRelatifURL(CheminActuel, CheminFutur: string): string;
    function FichierDestination(id: integer; url: string): string;
    function getDossierDeStockage: string;
    function URLEnFichier(url: string): string;
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

uses System.IOUtils, System.StrUtils, System.RegularExpressions;

function TForm1.TOAbsoluteURL(URL_EnCours, URL_ACharger: string): string;
var
  n: integer;
begin
  // on enlève la fin de l'URL en cours si elle contient un pseudo lien
  n := URL_EnCours.IndexOf('#');
  if n >= 0 then
    URL_EnCours := URL_EnCours.remove(n);
  // on enlève la fin de l'URL en cours si elle contient des infos en GET
  n := URL_EnCours.IndexOf('?');
  if n >= 0 then
    URL_EnCours := URL_EnCours.remove(n);
  // on enlève la fin de l'URL en cours si elle contient du HTML encodé
  n := URL_EnCours.IndexOf('&');
  if n >= 0 then
    URL_EnCours := URL_EnCours.remove(n);
  // on enlève la fin de l'URL si elle contient un pseudo lien
  n := URL_ACharger.IndexOf('#');
  if n >= 0 then
    URL_ACharger := URL_ACharger.remove(n);
  // on enlève la fin de l'URL si elle contient du HTML encodé
  // n := URL_ACharger.IndexOf('&');
  // if n >= 0 then
  // URL_ACharger:=URL_ACharger.remove(n);

  if (URL_ACharger.StartsWith('http://') or URL_ACharger.StartsWith('https://'))
  then // TODO : vérifier que le domaine est toujours le même pour ne pas télécharger tout internet !
    // si la nouvelle URL est une URL absolue, on l'ouvre
    result := URL_ACharger
  else if (URL_ACharger.StartsWith('/')) then
    // si la nouvelle URL est relative au domaine, on l'ajoute au domaine en cours
    // 9 = nb de caractères pour "https://"
    result := URL_EnCours.Substring(0, URL_EnCours.IndexOf('/', 9)) +
      URL_ACharger
  else if (URL_EnCours.LastIndexOf('/') >= 0) then
    // si la nouvelle URL était en relative, on l'ajoute à l'URL de la page en cours
    result := URL_EnCours.Substring(0, URL_EnCours.LastIndexOf('/') + 1) +
      URL_ACharger
  else // TODO : gérer l'absence de '/' final dans URL de départ
    result := '';
  // URL_EnCours.Substring(0, URL_EnCours.LastIndexOf('/')) +      URL_ACharger;
end;

function TForm1.ToRelatifURL(CheminActuel, CheminFutur: string): string;
var
  n: integer;
begin
  n := CheminActuel.IndexOf(tpath.DirectorySeparatorChar);
  while (n >= 0) and (CheminFutur.StartsWith(CheminActuel.Substring(0, n))) do
  begin
    CheminFutur := CheminFutur.remove(0, n + 1);
    CheminActuel := CheminActuel.remove(0, n + 1);
    n := CheminActuel.IndexOf(tpath.DirectorySeparatorChar);
  end;
  while (n >= 0) do
  begin
    CheminFutur := '..' + tpath.DirectorySeparatorChar + CheminFutur;
    CheminActuel := CheminActuel.remove(0, n + 1);
    n := CheminActuel.IndexOf(tpath.DirectorySeparatorChar);
  end;
  result := CheminFutur.Replace(tpath.DirectorySeparatorChar, '/');
end;

function TForm1.URLEnFichier(url: string): string;
var
  c: char;
  i: integer;
begin
  result := '';
  for i := 0 to url.Length - 1 do
    if (url.Chars[i] in ['a' .. 'z', '0' .. '9', 'A' .. 'Z']) then
      result := result + url.Chars[i]
    else if (url.Chars[i] = '/') and
      (not result.EndsWith(tpath.DirectorySeparatorChar)) then
      result := result + tpath.DirectorySeparatorChar;
end;

procedure TForm1.btnGoClick(Sender: TObject);
var
  url: string;
begin
  url := edtURL.Text.Trim;
  if not url.isempty then
    ChargerURL('', url);
end;

function TForm1.ChargerURL(URL_EnCours, URL_ACharger: string): string;
var
  id: integer; // ID du fichier dans la table et dans les noms de fichiers
  URL_Fichier: string; // URL absolue pour ce fichier
  Nom_Fichier: string; // nom du fichier stocké en local
  webResponse: IHTTPResponse;
  src: string;
  regex: tregex;
  regexlist: tmatchcollection;
  regexitem: tmatch;
  url: string;
  p: integer;
  BaseURL: string;
  FichierDeRemplacement: string;
  SrcModifie: boolean;
begin
  result := '';
  // TODO : add list of "not capture" URL (or use robots.txt)
  // if ((not URL_ACharger.Contains('spip.php?page=backend')) and
  // (not URL_ACharger.Contains('spip.php?page=login'))) then
  // begin
  id := tabURLDuSiteAAspirer.RecordCount + 1;
  URL_Fichier := TOAbsoluteURL(URL_EnCours, URL_ACharger);
  // on traite le fichier si son URL existe et qu'elle est sur le domaine demandé
  if (not URL_Fichier.isempty) and URL_Fichier.StartsWith(URL_EnCours) then
  begin
    // vérifier si l'URL a déjà été traitée
    result := DB.ExecSQLScalar
      ('select Nom_Fichier from URL where URL_Source=:url', [URL_Fichier]);
    if result.isempty then
    begin
      // Le fichier n'existait pas encore, on calcule son chemin et son nom
      Nom_Fichier := FichierDestination(id, URL_Fichier);
      result := Nom_Fichier;
      // si l'URL est inconnue, l'ajouter au fichier
      tabURLDuSiteAAspirer.Append;
      tabURLDuSiteAAspirer.FieldByName('id').AsInteger := id;
      tabURLDuSiteAAspirer.FieldByName('URL_Source').AsString := URL_Fichier;
      tabURLDuSiteAAspirer.FieldByName('Nom_Fichier').AsString := Nom_Fichier;
      tabURLDuSiteAAspirer.FieldByName('Enregistree').AsBoolean := false;
      tabURLDuSiteAAspirer.Post;
      sleep(10); // attente avant chaque chargement de page
      // on charge la page si c'est ok
      webResponse := web.Get(URL_Fichier);
      if webResponse.StatusCode = 200 then
      begin
        tabURLDuSiteAAspirer.Edit;
        tabURLDuSiteAAspirer.FieldByName('Enregistree').AsBoolean := true;
        tabURLDuSiteAAspirer.Post;
        // enregistrer le fichier avec son nouveau nom
        if not tdirectory.Exists
          (tpath.GetDirectoryName(tpath.combine(getDossierDeStockage,
          Nom_Fichier))) then
          tdirectory.CreateDirectory
            (tpath.GetDirectoryName(tpath.combine(getDossierDeStockage,
            Nom_Fichier)));
        var
        fs := tfilestream.Create(tpath.combine(getDossierDeStockage,
          Nom_Fichier), fmCreate);
        try
          fs.CopyFrom(webResponse.ContentStream);
        finally
          fs.Free;
        end;
        // on récupère le fichier si c'est du HTML et on en traite le contenu
        if (tpath.GetExtension(Nom_Fichier) = '.html') then
        begin
          src := tfile.ReadAllText(tpath.combine(getDossierDeStockage,
            Nom_Fichier), tencoding.ANSI);
          // TODO : gérer encodage par rapport au charset des pages (provenant des entêtes HTTP)
          SrcModifie := false;
          // récupération de l'URL de base si la page en a une
          regexitem := regex.Match(src, '<base[ ]+href[ ]*=[ ]*(["''])(.*?)\1',
            [roIgnoreCase]);
          if regexitem.Success then
          begin
            p := regexitem.Value.IndexOf('"');
            if p >= 0 then
            begin
              BaseURL := regexitem.Value.Substring(p + 1);
              BaseURL := BaseURL.Substring(0, BaseURL.Length - 1);
            end
            else
            begin
              p := regexitem.Value.IndexOf('''');
              if p >= 0 then
              begin
                BaseURL := regexitem.Value.Substring(p + 1);
                BaseURL := BaseURL.Substring(0, BaseURL.Length - 1);
              end
              else
                BaseURL := '';
            end;
            src := src.Replace(regexitem.Value, '<!-- old base href -->< ');
          end;
          // chargement des ressources de la page
          regexlist := regex.Matches(src, 'src[ ]*=[ ]*(["''])(.*?)\1',
            [roIgnoreCase]);
          for regexitem in regexlist do
          begin
            p := regexitem.Value.IndexOf('"');
            if p >= 0 then
            begin
              url := regexitem.Value.Substring(p + 1);
              url := url.Substring(0, url.Length - 1);
            end
            else
            begin
              p := regexitem.Value.IndexOf('''');
              if p >= 0 then
              begin
                url := regexitem.Value.Substring(p + 1);
                url := url.Substring(0, url.Length - 1);
              end
              else
                url := '';
            end;
            if not url.isempty then
            begin
              if not BaseURL.isempty then
                FichierDeRemplacement := ChargerURL(BaseURL, url)
              else
                FichierDeRemplacement := ChargerURL(URL_Fichier, url);
              if not FichierDeRemplacement.isempty then
              begin
                src := src.Replace(regexitem.Value,
                  'src="' + ToRelatifURL(Nom_Fichier, FichierDeRemplacement) +
                  '"', [rfReplaceAll]);
                SrcModifie := true;
              end;
            end;
          end;
          // recherche des pages liées
          regexlist := regex.Matches(src, 'href[ ]*=[ ]*(["''])(.*?)\1',
            [roIgnoreCase]);
          for regexitem in regexlist do
          begin
            p := regexitem.Value.IndexOf('"');
            if p >= 0 then
            begin
              url := regexitem.Value.Substring(p + 1);
              url := url.Substring(0, url.Length - 1);
            end
            else
            begin
              p := regexitem.Value.IndexOf('''');
              if p >= 0 then
              begin
                url := regexitem.Value.Substring(p + 1);
                url := url.Substring(0, url.Length - 1);
              end
              else
                url := '';
            end;
            if url.Length > 0 then
            begin
              FichierDeRemplacement := ChargerURL(URL_Fichier, url);
              if not FichierDeRemplacement.isempty then
              begin
                src := src.Replace(regexitem.Value,
                  'href="' + ToRelatifURL(Nom_Fichier, FichierDeRemplacement) +
                  '"', [rfReplaceAll]);
                SrcModifie := true;
              end;
            end;
          end;
          if SrcModifie then
            tfile.WriteAllText(tpath.combine(getDossierDeStockage, Nom_Fichier),
              src, tencoding.ANSI);
        end;
      end
      else
      begin
        tabURLDuSiteAAspirer.Edit;
        tabURLDuSiteAAspirer.FieldByName('Nom_Fichier').AsString :=
          'HTTP Error ' + webResponse.StatusCode.ToString + ' - ' +
          webResponse.StatusText;
        tabURLDuSiteAAspirer.Post;
      end;
    end;
  end;
  // end;
end;

function TForm1.FichierDestination(id: integer; url: string): string;
var
  extension: string;
begin // TODO : corriger cas étrange où l'extension prend aussi des paramètres GET lorsque ceux-ci sont sans query string
  var
  pos_last_separator := url.LastIndexOf('/');
  var
  pos_point := url.LastIndexOf('.');
  var
  pos_query := url.IndexOf('?');
  if pos_query < 0 then
    pos_query := url.IndexOf('&');

  if (pos_last_separator > pos_point) then
  // pas de point après le séparateur, on met du HTML en dur
  begin
    extension := 'html';
    pos_point := -1;
  end
  else if (pos_point >= 0) and (pos_point < pos_query) then
  // un point après le séparateur (s'il y en a un) et avant le "?"
  begin
    extension := url.Substring(pos_point + 1, pos_query - pos_point - 1);
    pos_point := -1;
  end
  else if (pos_point >= 0) and (0 <= pos_query) then
  // Un point est dispo après le "?", on considère que c'est du HTML quel que
  // soit le vrai format, car c'est une erreur de syntaxe dans la page d'origine
  begin
    extension := 'html';
    pos_point := -1;
  end
  else if (pos_point >= 0) then
    extension := url.Substring(pos_point + 1)
  else
    extension := 'html';

  if extension.StartsWith('htm') then
    extension := 'html' // tous les fichiers HTML seront en .html
  else if extension.StartsWith('php') then
    extension := 'html' // pas de PHP en local
  else if extension.StartsWith('exe') then
    extension := '_exe'; // protection contre les fichiers exécutables

  if (pos_point < 0) then
    result := URLEnFichier(url)
  else
    result := URLEnFichier(url.Substring(0, pos_point));

  if (result.isempty or result.EndsWith(tpath.DirectorySeparatorChar)) then
    result := result + 'index.' + extension
  else
    result := result + '.' + extension;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  if tabURLDuSiteAAspirer.Active then
    tabURLDuSiteAAspirer.close;
  tabURLDuSiteAAspirer.ResourceOptions.Persistent := true;
  tabURLDuSiteAAspirer.ResourceOptions.PersistentFileName :=
    tpath.combine(getDossierDeStockage, 'site.json');
  tabURLDuSiteAAspirer.open;
  edtURL.Text := 'https://olfsoftware.fr/';
  edtURL.SetFocus;
end;

function TForm1.getDossierDeStockage: string;
begin
  result := tpath.combine(tpath.GetDocumentsPath,
    tpath.GetFileNameWithoutExtension(paramstr(0)));
  if not tdirectory.Exists(result) then
    tdirectory.CreateDirectory(result);
end;

end.
