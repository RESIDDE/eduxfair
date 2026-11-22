import Nav from '../components/Nav';
import Footer from '../components/Footer';
import Hero from '../sections/Hero';
import Students from '../sections/Students';
import HowItWorks from '../sections/HowItWorks';
import Fairs from '../sections/Fairs';
import Safety from '../sections/Safety';
import Statement from '../sections/Statement';
import Institutions from '../sections/Institutions';
import GetApp from '../sections/GetApp';
import Faq, { ContactBand } from '../sections/Faq';

export default function Home() {
  return (
    <>
      <Nav />
      <main id="main">
        <Hero />
        <Students />
        <HowItWorks />
        <Fairs />
        <Safety />
        <Statement />
        <Institutions />
        <GetApp />
        <Faq />
      </main>
      <Footer>
        <ContactBand />
      </Footer>
    </>
  );
}
