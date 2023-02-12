import cloudscraper

scraper = cloudscraper.create_scraper()
print(scraper.get(sys.argv[1]).text)